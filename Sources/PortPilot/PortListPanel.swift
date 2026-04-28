import SwiftUI

// MARK: - Port List Panel
struct PortListPanel: View {
    @ObservedObject var viewModel: PortViewModel
    @ObservedObject private var appSettings = AppSettings.shared
    @Binding var selectedPort: PortProcess?
    let onKill: (Int) -> Void
    let onAdd: () -> Void
    /// I accept a shared history source so per-row sparklines render live data.
    /// Keeping this optional preserves existing call sites while letting ContentView inject it.
    var metrics: LiveMetricsHistory?

    var body: some View {
        VStack(spacing: 0) {
            // Column headers — richer Liquid Glass header with sparkline column
            PortListHeader()

            Divider()

            // Port list
            if viewModel.filteredPorts.isEmpty {
                PortListEmptyState(hasFilters: viewModel.hasActiveFilters, onClearFilters: {
                    viewModel.clearFilters()
                })
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
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
                                cpuUsage: port.cpuUsage,
                                history: metrics?.history(for: port) ?? []
                            )
                        }
                    }
                    .padding(.vertical, 4)
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
