import SwiftUI
import Combine
import AppKit

// Pure AppKit entry point — no SwiftUI App/Scene, so zero Dock icon
@main
enum PortPilotLauncher {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    let sharedViewModel = PortViewModel()
    private var autoRefreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enforce single instance
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if runningApps.count > 1 {
            for app in runningApps {
                if app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    app.activate(options: [.activateIgnoringOtherApps])
                    break
                }
            }
            NSApp.terminate(nil)
            return
        }

        // Ensure no Dock icon
        NSApp.setActivationPolicy(.accessory)

        // Apply settings
        AppSettings.shared.applyAllOnLaunch()
        sharedViewModel.forceKill = AppSettings.shared.defaultForceKill

        // Create menu bar
        menuBarController = MenuBarController(
            portViewModel: sharedViewModel,
            notificationManager: NotificationManager.shared
        )

        // Listen for requests
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleOpenMainWindow),
            name: .openMainWindow, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleMenuBarVisibility(_:)),
            name: .menuBarIconVisibilityChanged, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleAutoRefreshChanged),
            name: .autoRefreshChanged, object: nil
        )

        setupAutoRefreshTimer()
    }

    // MARK: - Main Window

    @objc private func handleOpenMainWindow() {
        openMainWindow()
    }

    func openMainWindow() {
        if let window = mainWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        let contentView = ContentView()
            .environmentObject(sharedViewModel)
            .frame(minWidth: 800, minHeight: 500)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 950, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PortPilot"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.setFrameAutosaveName("PortPilotMainWindow")
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        mainWindow = window
    }

    // MARK: - Settings Window

    func openSettingsWindow() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        let settingsView = SettingsView()
            .environmentObject(sharedViewModel)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PortPilot Settings"
        window.setContentSize(NSSize(width: 780, height: 560))
        window.contentMinSize = NSSize(width: 780, height: 560)
        window.toolbarStyle = .preference
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.setFrameAutosaveName("PortPilotSettingsWindow")
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        settingsWindow = window
    }

    // MARK: - Observers

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
