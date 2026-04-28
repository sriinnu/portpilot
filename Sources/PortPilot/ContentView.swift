import SwiftUI
import AppKit

// MARK: - Main Tab
enum MainTab: String, CaseIterable {
    case ports = "Ports"
    case schedules = "Schedules"
}

// MARK: - Content View
struct ContentView: View {
    @EnvironmentObject var viewModel: PortViewModel
    @ObservedObject private var appSettings = AppSettings.shared
    @StateObject private var metrics = LiveMetricsHistory()
    @StateObject private var palette = CommandPaletteController()
    @State private var showConfirmation = false
    @State private var portToKill: Int?
    @State private var selectedMainTab: MainTab = .ports
    @State private var selectedCronjob: CronjobEntry?
    @State private var inspectorTab: InspectorTab = .overview

    private var paletteActions: [CommandItem] {
        [
            CommandItem(
                icon: Theme.Icon.refresh,
                title: "Refresh Ports",
                subtitle: "Rescan open TCP/UDP sockets",
                tint: Theme.Action.refresh,
                action: { viewModel.refreshPorts() }
            ),
            CommandItem(
                icon: "stop.circle.fill",
                title: "Kill All Visible",
                subtitle: "Terminate every process in the current list",
                tint: Theme.Action.kill,
                action: { viewModel.killSelectedPorts(Set(viewModel.filteredPorts)) }
            ),
            CommandItem(
                icon: "clock.fill",
                title: "Go to Schedules",
                subtitle: "Switch to the cronjob tab",
                tint: Theme.Status.warning,
                action: { selectedMainTab = .schedules }
            ),
            CommandItem(
                icon: Theme.Icon.portsTab,
                title: "Go to Ports",
                subtitle: "Switch back to the port list",
                tint: Theme.Liquid.accentPurple,
                action: { selectedMainTab = .ports }
            ),
            CommandItem(
                icon: "waveform.path.ecg",
                title: "Open Metrics Tab",
                subtitle: "Show live CPU / memory for the selected port",
                tint: Theme.Status.warning,
                action: { inspectorTab = .metrics }
            ),
            CommandItem(
                icon: "text.alignleft",
                title: "Open Logs Tab",
                subtitle: "Tail the inspector log stream",
                tint: Theme.Action.treeView,
                action: { inspectorTab = .logs }
            ),
            CommandItem(
                icon: Theme.Icon.settings,
                title: "Open Settings",
                subtitle: "Theme, fonts, behavior",
                tint: Theme.Classification.system,
                action: {
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.openSettingsWindow()
                    }
                }
            )
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar with filter pills
            MainWindowToolbar(
                searchText: $viewModel.searchText,
                viewModel: viewModel,
                onRefresh: {
                    if selectedMainTab == .schedules {
                        viewModel.refreshCronjobs()
                    } else {
                        viewModel.refreshPorts()
                    }
                },
                onSettings: {
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.openSettingsWindow()
                    }
                },
                isLoading: selectedMainTab == .schedules ? viewModel.isLoadingCronjobs : viewModel.isLoading,
                portCount: viewModel.portCount,
                totalCount: viewModel.totalCount,
                selectedMainTab: $selectedMainTab
            )

            // Live traffic strip + protocol donut — ports tab only. Donut is
            // a live filter: tap a slice to restrict, tap again to clear.
            if selectedMainTab == .ports {
                HStack(spacing: 10) {
                    MainTrafficStrip(viewModel: viewModel, metrics: metrics)
                        .layoutPriority(1)
                    ProtocolDonut(
                        tcp: viewModel.ports.filter { $0.protocolName.lowercased() == "tcp" }.count,
                        udp: viewModel.ports.filter { $0.protocolName.lowercased() == "udp" }.count,
                        unix: viewModel.ports.filter { $0.isUnixSocket }.count,
                        onSelectTCP: {
                            viewModel.selectedProtocol = (viewModel.selectedProtocol == .tcp) ? .all : .tcp
                        },
                        onSelectUDP: {
                            viewModel.selectedProtocol = (viewModel.selectedProtocol == .udp) ? .all : .udp
                        },
                        onSelectUnix: {
                            viewModel.selectedProtocol = (viewModel.selectedProtocol == .unix) ? .all : .unix
                        },
                        selectedProtocol: {
                            switch viewModel.selectedProtocol {
                            case .tcp:  return "tcp"
                            case .udp:  return "udp"
                            case .unix: return "unix"
                            case .all:  return nil
                            }
                        }()
                    )
                    .padding(.trailing, 14).padding(.vertical, 10)
                }
                .background(Theme.Surface.groupedFill)
            }

            Divider()

            // Main content: sidebar + split list/inspector.
            HStack(spacing: 0) {
                LiquidSidebar(viewModel: viewModel, selectedMainTab: $selectedMainTab)

                HSplitView {
                    // Left pane: port list or cronjob list
                    if selectedMainTab == .schedules {
                        CronjobListPanel(
                            viewModel: viewModel,
                            selectedCronjob: $selectedCronjob
                        )
                        .frame(minWidth: 280, maxWidth: 440)
                    } else {
                        PortListPanel(
                            viewModel: viewModel,
                            selectedPort: $viewModel.selectedPort,
                            onKill: { port in
                                if appSettings.confirmBeforeKill {
                                    portToKill = port
                                    showConfirmation = true
                                } else {
                                    viewModel.killPort(port)
                                }
                            },
                            onAdd: {},
                            metrics: metrics
                        )
                        .frame(minWidth: 320, idealWidth: 420, maxWidth: 520)
                    }

                    // Right pane: inspector with tabs (Overview | Metrics | Logs)
                    VStack(spacing: 0) {
                        if selectedMainTab == .schedules {
                            CronjobConfigurationPanel(cronjob: selectedCronjob)
                            Divider()
                            CronjobLogsPanel(viewModel: viewModel)
                        } else {
                            InspectorTabBar(selection: $inspectorTab)
                            switch inspectorTab {
                            case .overview:
                                ConfigurationPanel(
                                    port: viewModel.selectedPort,
                                    viewModel: viewModel
                                )
                            case .metrics:
                                InspectorMetricsPane(
                                    port: viewModel.selectedPort,
                                    metrics: metrics,
                                    viewModel: viewModel
                                )
                            case .logs:
                                LogsPanel(viewModel: viewModel, selectedPort: viewModel.selectedPort)
                            }
                        }
                    }
                    .frame(minWidth: 360, idealWidth: 480)
                }
            }

            // Footer: live status bar — ports tab only.
            if selectedMainTab == .ports {
                MainStatusBar(viewModel: viewModel)
            }
        }
        .onAppear { metrics.start(viewModel: viewModel) }
        .onDisappear { metrics.stop() }
        // Command palette overlay — ⌘K toggles.
        .overlay {
            if palette.isPresented {
                CommandPaletteView(
                    controller: palette,
                    viewModel: viewModel,
                    actions: paletteActions,
                    onSelectPort: { port in
                        viewModel.selectedPort = port
                        selectedMainTab = .ports
                    }
                )
                .transition(.opacity)
            }
        }
        .background(
            Button(action: { palette.toggle() }) { Color.clear }
                .keyboardShortcut("k", modifiers: .command)
                .buttonStyle(.plain)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
        .animation(.easeInOut(duration: 0.18), value: palette.isPresented)
        .alert("Kill Process", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Kill", role: .destructive) {
                if let port = portToKill {
                    viewModel.killPort(port)
                }
            }
        } message: {
            if let port = portToKill {
                Text("Are you sure you want to terminate the process on port \(port)?")
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .overlay(alignment: .top) {
            if let success = viewModel.successMessage {
                SuccessToast(message: success)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !viewModel.proxySessions.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: Theme.Icon.proxyActive)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.Section.ssh)
                    Text("\(viewModel.proxySessions.count) active proxy")
                        .font(.system(size: 11, weight: .medium))
                    Button(action: { viewModel.stopAllProxies() }) {
                        Text("Stop All")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.Action.kill)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                )
                .padding(12)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: viewModel.successMessage)
        .onAppear {
            // Sync force kill setting
            viewModel.forceKill = appSettings.defaultForceKill
        }
    }
}

// MARK: - Success Toast
struct SuccessToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: Theme.Icon.checkmark)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Status.connected)
            Text(message)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .padding(.top, 12)
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .environmentObject(PortViewModel())
        .frame(width: 1000, height: 650)
}
