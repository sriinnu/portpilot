import SwiftUI
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
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private let mainNavigation = MainWindowNavigation()

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
            self, selector: #selector(handleOpenMainWindow(_:)),
            name: .openMainWindow, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleOpenSecurityCenter),
            name: .openSecurityCenter, object: nil
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

    @objc private func handleOpenMainWindow(_ notification: Notification) {
        openMainWindow(destination: notification.object as? MainTab)
    }

    @objc private func handleOpenSecurityCenter() {
        openMainWindow(destination: .security)
    }

    func openMainWindow(destination: MainTab? = nil) {
        if let destination { mainNavigation.selectedTab = destination }
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainWindow {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        let contentView = ContentView(navigation: mainNavigation)
            .environmentObject(sharedViewModel)
            .frame(minWidth: 900, minHeight: 650)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
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
                self?.sharedViewModel.refreshAllConnections()
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let session = PacketCaptureModel.activeSession else { return .terminateNow }
        session.cancel()
        Task {
            let finished = await Task.detached { session.waitUntilFinished(timeout: 4) }.value
            if !finished {
                let alert = NSAlert()
                alert.messageText = "Packet capture is still stopping"
                alert.informativeText = "PortPilot stayed open because capture cleanup has not finished. Try quitting again shortly."
                alert.runModal()
            }
            sender.reply(toApplicationShouldTerminate: finished)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppSettings.shared.refreshLaunchAtLoginStatus()
    }
}
