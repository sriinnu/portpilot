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
                                processUptime: viewModel.processUptime(for: port)
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer()
            Text("Actions")
                .font(.system(size: 11, weight: .semibold))
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

    @State private var isHovered = false

    private var infoTooltip: String {
        var lines: [String] = []
        lines.append("PID: \(port.pid)")
        if let ppid = port.parentPID {
            lines.append("PPID: \(ppid)" + (parentProcessName.map { " (\($0))" } ?? ""))
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
                .font(.system(size: 9, weight: .semibold))
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
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    } else {
                        Text(":\(port.port)")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    }
                    Text(port.protocolName.uppercased())
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.Surface.headerTint)
                        .cornerRadius(3)
                }
                Text(tunnelName ?? port.socketPath ?? port.fullCommand ?? port.command)
                    .font(.system(size: 11, design: .monospaced))
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
            isSelected
                ? Theme.Surface.selected
                : (isHovered ? Theme.Surface.hover : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
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
}

// MARK: - Empty State
struct PortListEmptyState: View {
    let hasFilters: Bool
    let onClearFilters: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: hasFilters ? "line.3.horizontal.decrease.circle" : "network.slash")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.5))
            Text(hasFilters ? "No matching ports" : "No ports found")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            if hasFilters {
                Button("Clear Filters") { onClearFilters() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Footer
struct PortListFooter: View {
    let onAdd: () -> Void

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
                        .font(.system(size: 12))
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
                        .font(.system(size: 12))
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
