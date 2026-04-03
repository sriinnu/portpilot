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
    @State private var showConfirmation = false
    @State private var portToKill: Int?
    @State private var selectedMainTab: MainTab = .ports
    @State private var selectedCronjob: CronjobEntry?

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

            Divider()

            // Main content: HSplitView
            HSplitView {
                // Left: Port list or Cronjob list
                if selectedMainTab == .schedules {
                    CronjobListPanel(
                        viewModel: viewModel,
                        selectedCronjob: $selectedCronjob
                    )
                    .frame(minWidth: 220, maxWidth: 350)
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
                        onAdd: {}
                    )
                    .frame(minWidth: 220, maxWidth: 350)
                }

                // Right: Config + Logs
                VStack(spacing: 0) {
                    if selectedMainTab == .schedules {
                        CronjobConfigurationPanel(cronjob: selectedCronjob)
                    } else {
                        ConfigurationPanel(
                            port: viewModel.selectedPort,
                            viewModel: viewModel
                        )
                    }

                    Divider()

                    if selectedMainTab == .ports {
                        LogsPanel(viewModel: viewModel, selectedPort: viewModel.selectedPort)
                    } else {
                        CronjobLogsPanel(viewModel: viewModel)
                    }
                }
                .frame(minWidth: 400)
            }
        }
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
        .frame(width: 900, height: 600)
}
