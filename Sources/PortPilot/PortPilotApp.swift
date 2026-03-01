import SwiftUI
import PortManagerLib
import Combine
import AppKit

@main
struct PortPilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appSettings = AppSettings.shared
    @StateObject private var notificationManager = NotificationManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.sharedViewModel)
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About PortPilot") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "PortPilot",
                            .applicationVersion: "1.0.0",
                            .credits: NSAttributedString(string: "Your port management companion")
                        ]
                    )
                }
            }

            CommandGroup(after: .appSettings) {
                Button("Refresh Ports") {
                    appDelegate.sharedViewModel.refreshPorts()
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Open Main Window") {
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()

                Toggle("Background Monitoring", isOn: $appSettings.backgroundMonitoring)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appDelegate.sharedViewModel)
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    let sharedViewModel = PortViewModel()
    private var autoRefreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply all saved settings on launch
        AppSettings.shared.applyAllOnLaunch()

        // Sync force kill setting
        sharedViewModel.forceKill = AppSettings.shared.defaultForceKill

        // Create menu bar controller using the shared view model
        menuBarController = MenuBarController(
            portViewModel: sharedViewModel,
            notificationManager: NotificationManager.shared
        )

        // Observe menu bar visibility changes
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleMenuBarVisibility(_:)),
            name: .menuBarIconVisibilityChanged, object: nil
        )

        // Observe auto-refresh changes
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleAutoRefreshChanged),
            name: .autoRefreshChanged, object: nil
        )

        // Start auto-refresh if enabled
        setupAutoRefreshTimer()
    }

    @objc private func handleMenuBarVisibility(_ notification: Notification) {
        guard let visible = notification.object as? Bool else { return }
        if visible {
            if menuBarController == nil {
                menuBarController = MenuBarController(
                    portViewModel: sharedViewModel,
                    notificationManager: NotificationManager.shared
                )
            }
        } else {
            menuBarController = nil
        }
    }

    @objc private func handleAutoRefreshChanged() {
        setupAutoRefreshTimer()
    }

    private func setupAutoRefreshTimer() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil

        let settings = AppSettings.shared
        guard settings.autoRefresh else { return }

        let interval = TimeInterval(settings.refreshInterval)
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sharedViewModel.refreshPorts()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
