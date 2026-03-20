import SwiftUI
import AppKit

// MARK: - Content View
struct ContentView: View {
    @EnvironmentObject var viewModel: PortViewModel
    @State private var showConfirmation = false
    @State private var portToKill: Int?

    private var appSettings: AppSettings { AppSettings.shared }

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar with filter pills
            MainWindowToolbar(
                searchText: $viewModel.searchText,
                viewModel: viewModel,
                onRefresh: { viewModel.refreshPorts() },
                onSettings: {
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.openSettingsWindow()
                    }
                },
                isLoading: viewModel.isLoading,
                portCount: viewModel.portCount,
                totalCount: viewModel.totalCount
            )

            Divider()

            // Main content: HSplitView
            HSplitView {
                // Left: Port list
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

                // Right: Config + Logs
                VStack(spacing: 0) {
                    ConfigurationPanel(
                        port: viewModel.selectedPort,
                        viewModel: viewModel
                    )

                    Divider()

                    LogsPanel(viewModel: viewModel, selectedPort: viewModel.selectedPort)
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
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
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
