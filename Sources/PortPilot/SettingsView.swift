import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: PortViewModel

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            MenuBarSettingsView()
                .tabItem {
                    Label("Menu Bar", systemImage: "menubar.rectangle")
                }

            NotificationsSettingsView()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 480, height: 380)
    }
}

// MARK: - General Settings
struct GeneralSettingsView: View {
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Auto-refresh ports", isOn: $appSettings.autoRefresh)

                if appSettings.autoRefresh {
                    Picker("Refresh interval", selection: $appSettings.refreshInterval) {
                        Text("15 seconds").tag(15)
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                        Text("5 minutes").tag(300)
                    }
                }
            } header: {
                Text("Refresh")
            }

            Section {
                Toggle("Confirm before killing processes", isOn: $appSettings.confirmBeforeKill)
                    .help("Show a confirmation dialog before killing a process")
                Toggle("Default to force kill", isOn: $appSettings.defaultForceKill)
                    .help("Use SIGKILL instead of SIGTERM when killing processes")
            } header: {
                Text("Behavior")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Appearance Settings
struct AppearanceSettingsView: View {
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $appSettings.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        HStack(spacing: 8) {
                            Image(systemName: iconForMode(mode))
                                .foregroundColor(colorForMode(mode))
                            Text(mode.rawValue)
                        }
                        .tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Choose between Light, Dark, or follow the System appearance.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                HStack(spacing: 16) {
                    // Light preview
                    AppearancePreviewCard(isDark: false, isActive: appSettings.appearanceMode == .light)
                    // Dark preview
                    AppearancePreviewCard(isDark: true, isActive: appSettings.appearanceMode == .dark)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            } header: {
                Text("Preview")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func iconForMode(_ mode: AppearanceMode) -> String {
        switch mode {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    private func colorForMode(_ mode: AppearanceMode) -> Color {
        switch mode {
        case .system: return .accentColor
        case .light: return Theme.Status.warning
        case .dark: return Theme.Section.ssh
        }
    }
}

// MARK: - Appearance Preview Card
struct AppearancePreviewCard: View {
    let isDark: Bool
    let isActive: Bool

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(isDark ? Color(white: 0.15) : Color(white: 0.95))
                .frame(width: 120, height: 70)
                .overlay(
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isDark ? Color(white: 0.25) : Color(white: 0.85))
                            .frame(height: 12)
                        HStack(spacing: 4) {
                            Circle().fill(Theme.Status.connected).frame(width: 6, height: 6)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(isDark ? Color(white: 0.3) : Color(white: 0.8))
                                .frame(height: 8)
                        }
                        HStack(spacing: 4) {
                            Circle().fill(Theme.Status.connected).frame(width: 6, height: 6)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(isDark ? Color(white: 0.3) : Color(white: 0.8))
                                .frame(height: 8)
                        }
                    }
                    .padding(8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
                )

            Text(isDark ? "Dark" : "Light")
                .font(.system(size: 11))
                .foregroundColor(isActive ? .primary : .secondary)
        }
    }
}

// MARK: - Menu Bar Settings
struct MenuBarSettingsView: View {
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show menu bar icon", isOn: $appSettings.showMenuBarIcon)
                    .help("Show or hide the PortPilot icon in the menu bar")

                Toggle("Show dock icon", isOn: $appSettings.showDockIcon)
                    .help("Show or hide the PortPilot icon in the Dock")

                if appSettings.showMenuBarIcon {
                    Toggle("Launch at login", isOn: $appSettings.launchAtLogin)
                        .help("Automatically start PortPilot when you log in")
                }
            } header: {
                Text("Visibility")
            } footer: {
                if !appSettings.showDockIcon && !appSettings.showMenuBarIcon {
                    Label("Warning: Both dock and menu bar icons are hidden. You may not be able to access the app.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(Theme.Status.warning)
                } else {
                    Text("When menu bar icon is shown, the app stays running in the background when you close the main window.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Picker("Auto-refresh interval", selection: $appSettings.autoRefreshInterval) {
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                }
            } header: {
                Text("Menu Bar Popover")
            } footer: {
                Text("How often to refresh the port list when the menu bar popover is open.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Notifications Settings
struct NotificationsSettingsView: View {
    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject private var notificationManager = NotificationManager.shared

    @State private var newWatchPort: String = ""

    var body: some View {
        Form {
            Section {
                Toggle("Enable notifications", isOn: $appSettings.showNotifications)
                    .help("Show notifications when watched ports change state")

                Toggle("Background monitoring", isOn: $appSettings.backgroundMonitoring)
                    .help("Continue monitoring ports when the app is running in the menu bar")
            } header: {
                Text("Notifications")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { notificationManager.isWatching },
                    set: { _ in notificationManager.toggleWatching() }
                )) {
                    HStack {
                        Image(systemName: notificationManager.isWatching ? Theme.Icon.connected : "antenna.slash")
                            .foregroundColor(notificationManager.isWatching ? Theme.Status.connected : .secondary)
                        Text(notificationManager.isWatching ? "Monitoring Active" : "Monitoring Paused")
                    }
                }
            } header: {
                Text("Port Monitoring")
            } footer: {
                Text("Toggle monitoring on/off. Port monitoring runs in the background when enabled.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                HStack {
                    TextField("Port number", text: $newWatchPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Button("Add Port") {
                        if let port = Int(newWatchPort), port > 0, port <= 65535 {
                            notificationManager.addWatchedPort(port)
                            newWatchPort = ""
                        }
                    }
                    .disabled(newWatchPort.isEmpty || Int(newWatchPort) == nil)
                }

                if !notificationManager.watchedPorts.isEmpty {
                    ForEach(notificationManager.watchedPorts, id: \.port) { watched in
                        HStack {
                            Circle()
                                .fill(watched.lastKnownState == .available ? Theme.Status.connected : (watched.lastKnownState == .occupied ? Theme.Status.error : Color.gray))
                                .frame(width: 8, height: 8)
                            Text("Port \(watched.port)")
                                .fontDesign(.monospaced)
                            Spacer()
                            Text(watched.lastKnownState == .available ? "Available" : (watched.lastKnownState == .occupied ? "Occupied" : "Unknown"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button(action: {
                                notificationManager.removeWatchedPort(watched.port)
                            }) {
                                Image(systemName: Theme.Icon.clearSearch)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            } header: {
                Text("Watched Ports")
            } footer: {
                Text("Add ports to watch. You'll receive notifications when these ports become available or occupied.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About Settings
struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.Action.treeView, Theme.Section.kubernetes],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("PortPilot")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 1.0.0")
                .foregroundColor(.secondary)

            Text("Your port management companion")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    SettingsView()
        .environmentObject(PortViewModel())
}
