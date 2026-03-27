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
                            Divider().padding(.leading, 12)
                        }
                    }
                }
            }

            Divider()

            // Bottom buttons
            PortListFooter(onAdd: onAdd)
        }
        .frame(minWidth: 220, idealWidth: 260)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
        HStack(spacing: 10) {
            // Favorite button
            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundColor(isFavorite ? .yellow : .gray)
            }
            .buttonStyle(.plain)
            .help(isFavorite ? "Remove from favorites" : "Add to favorites")
            .opacity(isFavorite || isHovered || isSelected ? 1 : 0.24)

            // Type indicator
            Image(systemName: typeIcon)
                .font(.system(size: 10))
                .foregroundColor(typeColor)
                .frame(width: 14)

            // Process type badge
            Text(processType.rawValue)
                .font(appSettings.appFont(size: max(appSettings.fontSize - 3, 8), weight: .semibold))
                .foregroundColor(processTypeColor(processType))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(processTypeColor(processType).opacity(0.14))
                )

            // Port info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if port.isUnixSocket {
                        Text("PID \(port.pid)")
                            .font(appSettings.appMonoFont(size: appSettings.fontSize + 1, weight: .semibold))
                    } else {
                        Text(":\(port.port)")
                            .font(appSettings.appMonoFont(size: appSettings.fontSize + 1, weight: .semibold))
                    }
                    Text(port.protocolName.uppercased())
                        .font(appSettings.appMonoFont(size: max(appSettings.fontSize - 3, 8), weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.Surface.headerTint)
                        .cornerRadius(3)

                    // CPU badge — always visible
                    if let cpu = cpuUsage {
                        if cpu > 0.1 {
                            Text(String(format: "%.1f%%", cpu))
                                .font(appSettings.appMonoFont(size: max(appSettings.fontSize - 3, 8), weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(cpuHeatColor(cpu)))
                                .shadow(color: cpuHeatColor(cpu).opacity(0.35), radius: 3, y: 1)
                        } else {
                            Text("0%")
                                .font(appSettings.appMonoFont(size: max(appSettings.fontSize - 3, 8), weight: .medium))
                                .foregroundColor(.secondary.opacity(0.5))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1))
                        }
                    }

                    // Memory badge
                    if let mem = port.memoryMB {
                        Text(formatMemory(mem))
                            .font(appSettings.appMonoFont(size: max(appSettings.fontSize - 3, 8), weight: .medium))
                            .foregroundColor(.secondary.opacity(0.7))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1))
                    }
                }
                Text(tunnelName ?? port.socketPath ?? port.fullCommand ?? port.command)
                    .font(appSettings.appMonoFont(size: appSettings.fontSize - 1))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 6) {
                // Info indicator with tooltip
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
                    .help(infoTooltip)
                    .opacity(isHovered || isSelected ? 1 : 0.3)

                Button(action: onKill) {
                    Image(systemName: Theme.Icon.kill)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.Action.kill)
                }
                .buttonStyle(.plain)
                .help("Kill process")

            }
            .opacity(isHovered || isSelected ? 1 : 0.3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected
                    ? Theme.Surface.selected
                    : (isHovered ? Theme.Surface.hover : .clear))
                .shadow(color: isHovered && !isSelected ? Color.black.opacity(0.06) : .clear, radius: 3, y: 1)
        )
        .contentShape(Rectangle())
        .scaleEffect(isHovered && !isSelected ? 1.005 : 1.0)
        .onTapGesture { onSelect() }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) { isHovered = hovering }
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
            .opacity(0.72)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
