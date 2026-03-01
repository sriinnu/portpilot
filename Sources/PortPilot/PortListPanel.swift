import SwiftUI
import PortManagerLib

// MARK: - Port List Panel
struct PortListPanel: View {
    @ObservedObject var viewModel: PortViewModel
    @Binding var selectedPort: PortProcess?
    let onKill: (Int) -> Void

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
                        ForEach(viewModel.filteredPorts, id: \.port) { port in
                            PortListRow(
                                port: port,
                                isSelected: selectedPort?.port == port.port,
                                onSelect: { selectedPort = port },
                                onKill: { onKill(port.port) },
                                typeColor: viewModel.connectionType(for: port).color,
                                typeIcon: viewModel.connectionType(for: port).icon,
                                tunnelName: viewModel.tunnelName(for: port)
                            )
                            Divider().padding(.leading, 12)
                        }
                    }
                }
            }

            Divider()

            // Bottom buttons
            PortListFooter()
        }
        .frame(minWidth: 220, idealWidth: 260)
        .background(Theme.Surface.controlBackground)
    }
}

// MARK: - Column Headers
struct PortListHeader: View {
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
        .background(Theme.Surface.windowBackground.opacity(0.5))
    }
}

// MARK: - Port Row
struct PortListRow: View {
    let port: PortProcess
    let isSelected: Bool
    let onSelect: () -> Void
    let onKill: () -> Void
    var typeColor: Color = Theme.Status.connected
    var typeIcon: String = Theme.Icon.local
    var tunnelName: String? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Type indicator
            Image(systemName: typeIcon)
                .font(.system(size: 10))
                .foregroundColor(typeColor)
                .frame(width: 14)

            // Port info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(":\(port.port)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text(port.protocolName.uppercased())
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
                        .cornerRadius(3)
                }
                Text(tunnelName ?? port.command)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 6) {
                Button(action: onKill) {
                    Image(systemName: Theme.Icon.kill)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.Action.kill)
                }
                .buttonStyle(.plain)
                .help("Kill process")

                Button(action: onKill) {
                    Image(systemName: Theme.Icon.trash)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Action.kill)
                }
                .buttonStyle(.plain)
                .help("Remove")
            }
            .opacity(isHovered || isSelected ? 1 : 0.3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
    var body: some View {
        HStack(spacing: 8) {
            Button(action: {}) {
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
            .help("Add port forward (coming soon)")

            Button(action: {}) {
                HStack(spacing: 4) {
                    Image(systemName: Theme.Icon.importFile)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.Action.importAction)
                    Text("Import")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Action.importAction)
                }
            }
            .buttonStyle(.plain)
            .help("Import configuration (coming soon)")

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
