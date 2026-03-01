import SwiftUI
import AppKit
import UserNotifications
import PortManagerLib
import Combine

// MARK: - Menu Bar Controller
class MenuBarController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private var panel: MenuBarPanel?
    private var eventMonitor: Any?
    private let portViewModel: PortViewModel
    private let notificationManager: NotificationManager

    @Published var isPanelShown = false

    init(portViewModel: PortViewModel, notificationManager: NotificationManager) {
        self.portViewModel = portViewModel
        self.notificationManager = notificationManager
        super.init()
        setupMenuBar()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }

        button.image = makeTemplateMenuBarIcon(symbolName: "network")
        button.imagePosition = .imageLeading

        button.action = #selector(togglePanel)
        button.target = self

        // Global event monitor for outside-click dismiss
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissPanel()
        }
    }

    @objc private func togglePanel() {
        if isPanelShown {
            dismissPanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem?.button else { return }

        let panelWidth: CGFloat = 320
        let panelHeight: CGFloat = 580

        if panel == nil {
            panel = MenuBarPanel(contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        }

        let dropdownView = MenuBarDropdownView(
            viewModel: portViewModel,
            onOpenMainWindow: { [weak self] in
                Task { @MainActor in
                    self?.openMainWindow()
                }
            },
            onQuit: {
                NSApp.terminate(nil)
            },
            onDismiss: { [weak self] in
                self?.dismissPanel()
            },
            onOpenSettings: { [weak self] in
                self?.openSettings()
            },
            onSponsors: { [weak self] in
                self?.openSponsors()
            }
        )

        panel?.setSwiftUIContent(dropdownView)
        panel?.setContentSize(NSSize(width: panelWidth, height: panelHeight))
        panel?.showBelow(button: button)
        isPanelShown = true

        Task { @MainActor in
            portViewModel.refreshPorts()
        }
    }

    private func dismissPanel() {
        guard isPanelShown else { return }
        panel?.close()
        isPanelShown = false
    }

    private func openSettings() {
        dismissPanel()
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    private func openSponsors() {
        dismissPanel()
        if let url = URL(string: "https://github.com/sponsors/nicklama") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor func openMainWindow() {
        dismissPanel()
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
    }

    @MainActor func showPopover() {
        if !isPanelShown {
            showPanel()
        }
    }

    @MainActor func updateMenuBarIcon(activePorts: Int) {
        if let button = statusItem?.button {
            let symbolName = activePorts > 0 ? "network" : "network.slash"
            button.image = makeTemplateMenuBarIcon(symbolName: symbolName)
        }
    }

    /// Renders an SF Symbol as a native macOS template menu bar icon.
    private func makeTemplateMenuBarIcon(symbolName: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "PortPilot")?
            .withSymbolConfiguration(config) else {
            return NSImage()
        }
        image.isTemplate = true
        return image
    }

    deinit {
        if let eventMonitor = eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let openMainWindow = Notification.Name("openMainWindow")
    static let addWatchedPort = Notification.Name("addWatchedPort")
}

// MARK: - Notification Manager
class NotificationManager: NSObject, ObservableObject, PortWatcherDelegate {
    private let portWatcher: PortWatcher
    private let portManager = PortManager()

    @Published var watchedPorts: [WatchedPort] = []
    @Published var isWatching: Bool = false
    @Published var notificationsEnabled: Bool = true

    override init() {
        self.portWatcher = PortWatcher(portManager: portManager)
        super.init()
        self.portWatcher.delegate = self
        loadWatchedPorts()
        requestNotificationPermissions()
    }

    private func requestNotificationPermissions() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    func addWatchedPort(_ port: Int, protocolName: String = "tcp") {
        portWatcher.addPort(port, protocolName: protocolName)
        watchedPorts = portWatcher.getWatchedPorts()
        saveWatchedPorts()
    }

    func removeWatchedPort(_ port: Int) {
        portWatcher.removePort(port)
        watchedPorts = portWatcher.getWatchedPorts()
        saveWatchedPorts()
    }

    func startWatching() {
        portWatcher.startWatching()
        isWatching = true
    }

    func stopWatching() {
        portWatcher.stopWatching()
        isWatching = false
    }

    func toggleWatching() {
        if isWatching { stopWatching() } else { startWatching() }
    }

    // MARK: - PortWatcherDelegate

    func portWatcher(_ watcher: PortWatcher, portBecameAvailable port: Int) {
        guard notificationsEnabled else { return }
        sendNotification(
            title: "Port Available",
            body: "Port \(port) is now available",
            identifier: "port-\(port)-available"
        )
    }

    func portWatcher(_ watcher: PortWatcher, portBecameOccupied port: Int) {
        guard notificationsEnabled else { return }
        do {
            let processes = try portManager.getListeningProcesses(startPort: port, endPort: port)
            if let process = processes.first {
                sendNotification(
                    title: "Port Occupied",
                    body: "Port \(port) is now in use by \(process.command) (PID: \(process.pid))",
                    identifier: "port-\(port)-occupied"
                )
            }
        } catch {
            sendNotification(
                title: "Port Occupied",
                body: "Port \(port) is now in use",
                identifier: "port-\(port)-occupied"
            )
        }
    }

    func portWatcher(_ watcher: PortWatcher, didUpdateState state: PortState, forPort port: Int) {
        watchedPorts = portWatcher.getWatchedPorts()
    }

    private func sendNotification(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error)")
            }
        }
    }

    // MARK: - Persistence

    private func saveWatchedPorts() {
        let ports = watchedPorts.map { $0.port }
        UserDefaults.standard.set(ports, forKey: "WatchedPorts")
    }

    private func loadWatchedPorts() {
        if let ports = UserDefaults.standard.array(forKey: "WatchedPorts") as? [Int] {
            for port in ports {
                portWatcher.addPort(port)
            }
            watchedPorts = portWatcher.getWatchedPorts()
        }
    }
}

// MARK: - Global Notification Manager Singleton
extension NotificationManager {
    static let shared = NotificationManager()
}
