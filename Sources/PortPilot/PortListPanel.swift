import SwiftUI

// MARK: - Port List Panel
struct PortListPanel: View {
    @ObservedObject var viewModel: PortViewModel
    @ObservedObject private var appSettings = AppSettings.shared
    @Binding var selectedPort: PortProcess?
    let onKill: (Int) -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Column headers
            PortListHeader()

            Divider()

            // Port list
            if viewModel.filteredPorts.isEmpty {
                PortListEmptyState(hasFilters: viewModel.hasActiveFilters, onClearFilters: {
                    viewModel.clearFilters()
                })
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.filteredPorts, id: \.id) { port in
                            PortListRow(
                                port: port,
                                isSelected: selectedPort?.port == port.port,
                                isFavorite: viewModel.isFavorite(port: port.port),
                                onSelect: { selectedPort = port },
                                onKill: { onKill(port.port) },
                                onToggleFavorite: { viewModel.toggleFavorite(port: port.port) },
                                processType: viewModel.processType(for: port),
                                typeColor: viewModel.connectionType(for: port).color,
                                typeIcon: viewModel.connectionType(for: port).icon,
                                tunnelName: viewModel.tunnelName(for: port),
                                parentProcessName: viewModel.parentProcessName(for: port),
                                processUptime: viewModel.processUptime(for: port),
                                cpuUsage: port.cpuUsage
                            )
                            Divider().padding(.leading, Theme.Spacing.contentInset)
                        }
                    }
                }
            }

            Divider()

            // Bottom buttons
            PortListFooter(onAdd: onAdd)
        }
        .frame(minWidth: 300, idealWidth: 340)
        .background(Theme.Surface.controlBackground)
    }
}

// MARK: - Column Headers
struct PortListHeader: View {
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        HStack {
            Text("Port")
                .font(appSettings.appFont(size: appSettings.fontSize - 1, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer()
            Text("Actions")
                .font(appSettings.appFont(size: appSettings.fontSize - 1, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, Theme.Spacing.contentInset)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Surface.headerTint)
    }
}

// MARK: - Port Row
struct PortListRow: View {
    let port: PortProcess
    let isSelected: Bool
    let isFavorite: Bool
    let onSelect: () -> Void
    let onKill: () -> Void
    let onToggleFavorite: () -> Void
    var processType: ProcessType = .other
    var typeColor: Color = Theme.Status.connected
    var typeIcon: String = Theme.Icon.local
    var tunnelName: String? = nil
    var parentProcessName: String? = nil
    var processUptime: String? = nil
    var cpuUsage: Double? = nil

    @ObservedObject private var appSettings = AppSettings.shared
    @State private var isHovered = false

    private var infoTooltip: String {
        var lines: [String] = []
        lines.append("PID: \(port.pid)")
        if let ppid = port.parentPID {
            lines.append("PPID: \(ppid)" + (parentProcessName.map { " (\($0))" } ?? ""))
        }
        if let cpu = cpuUsage {
            lines.append("CPU: \(String(format: "%.1f", cpu))%")
        }
        if let mem = port.memoryMB {
            lines.append("Memory: \(formatMemory(mem))")
        }
        if let uptime = processUptime {
            lines.append("Uptime: \(uptime)")
        }
        if let cwd = port.workingDirectory, !cwd.isEmpty {
            lines.append("CWD: \(cwd)")
        }
        if let fullCmd = port.fullCommand, !fullCmd.isEmpty {
            lines.append("Command: \(fullCmd)")
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Favorite button
            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundColor(isFavorite ? .yellow : .gray)
            }
            .buttonStyle(.plain)
            .frame(width: Theme.Size.hitTargetMin, height: Theme.Size.hitTargetMin)
            .contentShape(Rectangle())
            .help(isFavorite ? "Remove from favorites" : "Add to favorites")
            .opacity(isFavorite || isHovered || isSelected ? 1 : Theme.Opacity.disabled)

            // Type indicator
            Image(systemName: typeIcon)
                .font(.system(size: 10))
                .foregroundColor(typeColor)
                .frame(width: 14)

            // Port info — port number is the dominant element
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    if port.isUnixSocket {
                        Text("PID \(String(port.pid))")
                            .font(appSettings.appMonoFont(size: appSettings.fontSize + 2, weight: .bold))
                            .fixedSize()
                    } else {
                        Text(":\(String(port.port))")
                            .font(appSettings.appMonoFont(size: appSettings.fontSize + 2, weight: .bold))
                            .fixedSize()
                    }
                    Text(port.protocolName.uppercased())
                        .font(appSettings.appMonoFont(size: max(appSettings.fontSize - 3, 8), weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.Surface.headerTint)
                        .cornerRadius(Theme.Size.cornerRadiusSmall)
                        .fixedSize()
                }

                // Second line: process type badge + command name
                HStack(spacing: Theme.Spacing.xs) {
                    Text(processType.rawValue)
                        .font(appSettings.appFont(size: max(appSettings.fontSize - 3, 8), weight: .semibold))
                        .foregroundColor(processTypeColor(processType))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Size.cornerRadiusSmall)
                                .fill(processTypeColor(processType).opacity(0.14))
                        )

                    Text(tunnelName ?? port.socketPath ?? port.fullCommand ?? port.command)
                        .font(appSettings.appMonoFont(size: appSettings.fontSize - 1))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            // Stats — subtle, right-aligned
            HStack(spacing: Theme.Spacing.xs) {
                if let cpu = cpuUsage {
                    if cpu > 0.1 {
                        Text(String(format: "%.0f%%", cpu))
                            .font(appSettings.appMonoFont(size: max(appSettings.fontSize - 3, 8), weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(cpuHeatColor(cpu)))
                            .fixedSize()
                    } else {
                        Text("0%")
                            .font(appSettings.appMonoFont(size: max(appSettings.fontSize - 3, 8), weight: .medium))
                            .foregroundColor(.secondary.opacity(0.5))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1))
                            .fixedSize()
                    }
                }

                if let mem = port.memoryMB {
                    Text(formatMemory(mem))
                        .font(appSettings.appMonoFont(size: max(appSettings.fontSize - 3, 8), weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1))
                        .fixedSize()
                }
            }

            // Action buttons
            HStack(spacing: 6) {
                // Info indicator with tooltip
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
                    .help(infoTooltip)
                    .opacity(isHovered || isSelected ? 1 : Theme.Opacity.disabled)

                Button(action: onKill) {
                    Image(systemName: Theme.Icon.kill)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.Action.kill)
                }
                .buttonStyle(.plain)
                .frame(width: Theme.Size.hitTargetMin, height: Theme.Size.hitTargetMin)
                .contentShape(Rectangle())
                .help("Kill process")
            }
            .opacity(isHovered || isSelected ? 1 : Theme.Opacity.disabled)
        }
        .padding(.horizontal, Theme.Spacing.contentInset)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Size.cornerRadius)
                .fill(isSelected
                    ? Theme.Surface.selected
                    : (isHovered ? Theme.Surface.hover : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) { isHovered = hovering }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func processTypeColor(_ type: ProcessType) -> Color {
        switch type {
        case .system: return Theme.Classification.system
        case .userApp: return Theme.Classification.userApp
        case .developerTool: return Theme.Classification.developerTool
        case .other: return Theme.Classification.other
        }
    }

    private func formatMemory(_ mb: Double) -> String {
        if mb >= 1024 { return String(format: "%.1fG", mb / 1024.0) }
        if mb >= 10 { return String(format: "%.0fM", mb) }
        return String(format: "%.1fM", mb)
    }

    /// Smooth heat-map: 0% teal → 25% blue → 50% amber → 75% orange → 100% red
    private func cpuHeatColor(_ usage: Double) -> Color {
        let t = min(max(usage / 100.0, 0), 1)
        let r: Double, g: Double, b: Double
        if t < 0.25 {
            let p = t / 0.25
            r = 0.18 + p * 0.12;  g = 0.62 - p * 0.14;  b = 0.70 - p * 0.02
        } else if t < 0.50 {
            let p = (t - 0.25) / 0.25
            r = 0.30 + p * 0.58;  g = 0.48 + p * 0.14;  b = 0.68 - p * 0.52
        } else if t < 0.75 {
            let p = (t - 0.50) / 0.25
            r = 0.88 + p * 0.07;  g = 0.62 - p * 0.22;  b = 0.16 - p * 0.04
        } else {
            let p = (t - 0.75) / 0.25
            r = 0.95 - p * 0.05;  g = 0.40 - p * 0.18;  b = 0.12 + p * 0.08
        }
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Empty State
struct PortListEmptyState: View {
    let hasFilters: Bool
    let onClearFilters: () -> Void
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: hasFilters ? "line.3.horizontal.decrease.circle" : "network.slash")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.5))
            Text(hasFilters ? "No matching ports" : "No ports found")
                .font(appSettings.appFont(size: appSettings.fontSize + 1, weight: .medium))
                .foregroundColor(.secondary)
            if hasFilters {
                Button("Clear Filters") { onClearFilters() }
                    .buttonStyle(.plain)
                    .font(appSettings.appFont(size: appSettings.fontSize))
                    .foregroundColor(.accentColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Footer
struct PortListFooter: View {
    let onAdd: () -> Void
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onAdd) {
                HStack(spacing: 4) {
                    // Green filled circle with white "+"
                    ZStack {
                        Circle()
                            .fill(Theme.Action.add)
                            .frame(width: 16, height: 16)
                        Image(systemName: Theme.Icon.add)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("Add")
                        .font(appSettings.appFont(size: appSettings.fontSize))
                        .foregroundColor(Theme.Action.add)
                }
            }
            .buttonStyle(.plain)
            .help("Add port forward")

            Button(action: {}) {
                HStack(spacing: 4) {
                    Image(systemName: Theme.Icon.importFile)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("Import")
                        .font(appSettings.appFont(size: appSettings.fontSize))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("Import configuration (coming soon)")
            .opacity(Theme.Opacity.secondary)

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.contentInset)
        .padding(.vertical, Theme.Spacing.sm)
    }
}
