import SwiftUI
import AppKit
import UserNotifications
import Combine

// MARK: - Menu Bar Controller
@MainActor
class MenuBarController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private var panel: MenuBarPanel?
    nonisolated(unsafe) private var eventMonitor: Any?
    private let portViewModel: PortViewModel
    private let notificationManager: NotificationManager

    @Published var isPanelShown = false

    nonisolated(unsafe) private var metricsTimer: Timer?

    init(portViewModel: PortViewModel, notificationManager: NotificationManager) {
        self.portViewModel = portViewModel
        self.notificationManager = notificationManager
        super.init()
        setupMenuBar()
        startMetricsUpdates()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else {
            print("MenuBarController: Failed to get status item button")
            return
        }

        // SF Symbol — configure BEFORE assigning to button
        if let icon = NSImage(systemSymbolName: "network.badge.shield.half.filled",
                              accessibilityDescription: "PortPilot") {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let configured = icon.withSymbolConfiguration(config) ?? icon
            configured.size = NSSize(width: 18, height: 18)
            configured.isTemplate = true
            button.image = configured
        } else {
            button.title = "PP"
        }

        button.action = #selector(togglePanel)
        button.target = self
    }

    private func startMetricsUpdates() {
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCapsuleMetrics()
            }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.refreshCapsuleMetrics()
        }
    }

    private func refreshCapsuleMetrics() {
        let alertState: AlertState = portViewModel.alertState
        updateMenuBarIcon(alertState: alertState)
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

        let panelWidth = Theme.Liquid.panelWidth
        let panelHeight = Theme.Liquid.panelHeight

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

        // Scope event monitor to when panel is open
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissPanel()
        }

        Task { [weak self] in
            self?.portViewModel.refreshPorts()
            self?.portViewModel.refreshAllConnections()
            self?.refreshCapsuleMetrics()
        }
    }

    private func dismissPanel() {
        guard isPanelShown else { return }
        panel?.close()
        panel = nil
        isPanelShown = false

        // Remove event monitor when panel closes
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func openSettings() {
        dismissPanel()
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.openSettingsWindow()
        }
    }

    private func openSponsors() {
        dismissPanel()
        if let url = URL(string: "https://github.com/sponsors/sriinnu") {
            NSWorkspace.shared.open(url)
        }
    }

    func openMainWindow() {
        dismissPanel()
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
    }

    func showPopover() {
        if !isPanelShown {
            showPanel()
        }
    }

    func updateMenuBarIcon(alertState: AlertState = .normal) {
        guard let button = statusItem?.button else { return }

        let symbolName = alertState == .critical
            ? "exclamationmark.triangle.fill"
            : "network.badge.shield.half.filled"

        if let icon = NSImage(systemSymbolName: symbolName, accessibilityDescription: "PortPilot") {
            icon.size = NSSize(width: 18, height: 18)
            icon.isTemplate = alertState != .critical
            button.image = icon
        } else {
            button.title = "PP"
        }
    }


    deinit {
        if let eventMonitor = eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        metricsTimer?.invalidate()
    }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let openMainWindow = Notification.Name("openMainWindow")
    static let addWatchedPort = Notification.Name("addWatchedPort")
}

// MARK: - Notification Manager
class NotificationManager: NSObject, ObservableObject, PortWatcherDelegate, UNUserNotificationCenterDelegate {
    private let portWatcher: PortWatcher
    private let portManager = PortManager()

    @Published var watchedPorts: [WatchedPort] = []
    @Published var isWatching: Bool = false
    @Published var notificationsEnabled: Bool = true

    // Notification action identifiers
    static let killActionIdentifier = "KILL_ACTION"
    static let copyPortActionIdentifier = "COPY_PORT_ACTION"
    static let dismissActionIdentifier = "DISMISS_ACTION"
    static let viewConnectionsActionIdentifier = "VIEW_CONNECTIONS_ACTION"
    static let killProcessActionIdentifier = "KILL_PROCESS_ACTION"

    // Notification category identifiers
    static let portOccupiedCategoryIdentifier = "PORT_OCCUPIED"
    static let portAvailableCategoryIdentifier = "PORT_AVAILABLE"
    static let reservedPortCategoryIdentifier = "RESERVED_PORT"
    static let connectionAlertCategoryIdentifier = "CONNECTION_ALERT"

    override init() {
        self.portWatcher = PortWatcher(portManager: portManager)
        super.init()
        self.portWatcher.delegate = self
        UNUserNotificationCenter.current().delegate = self
        loadWatchedPorts()
        registerNotificationCategories()
        requestNotificationPermissions()
    }

    private func registerNotificationCategories() {
        let center = UNUserNotificationCenter.current()

        let killAction = UNNotificationAction(
            identifier: Self.killActionIdentifier,
            title: "Kill",
            options: [.destructive, .authenticationRequired]
        )

        let copyPortAction = UNNotificationAction(
            identifier: Self.copyPortActionIdentifier,
            title: "Copy Port",
            options: [.foreground]
        )

        let dismissAction = UNNotificationAction(
            identifier: Self.dismissActionIdentifier,
            title: "Dismiss",
            options: [.destructive]
        )

        let portOccupiedCategory = UNNotificationCategory(
            identifier: Self.portOccupiedCategoryIdentifier,
            actions: [killAction, copyPortAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let portAvailableCategory = UNNotificationCategory(
            identifier: Self.portAvailableCategoryIdentifier,
            actions: [copyPortAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let reservedPortCategory = UNNotificationCategory(
            identifier: Self.reservedPortCategoryIdentifier,
            actions: [killAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let viewConnectionsAction = UNNotificationAction(
            identifier: Self.viewConnectionsActionIdentifier,
            title: "View Connections",
            options: [.foreground]
        )

        let connectionAlertCategory = UNNotificationCategory(
            identifier: Self.connectionAlertCategoryIdentifier,
            actions: [viewConnectionsAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        center.setNotificationCategories([
            portOccupiedCategory,
            portAvailableCategory,
            reservedPortCategory,
            connectionAlertCategory
        ])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let port = userInfo["port"] as? Int ?? 0
        let identifier = response.actionIdentifier

        switch identifier {
        case Self.killActionIdentifier:
            Task {
                try? portManager.killProcessOnPort(port, force: true)
            }
        case Self.copyPortActionIdentifier:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(String(port), forType: .string)
        case Self.dismissActionIdentifier:
            break
        default:
            break
        }

        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
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
            identifier: "port-\(port)-available",
            categoryIdentifier: Self.portAvailableCategoryIdentifier,
            userInfo: ["port": port]
        )
    }

    func portWatcher(_ watcher: PortWatcher, portBecameOccupied port: Int) {
        guard notificationsEnabled else { return }
        do {
            let processes = try portManager.getListeningProcesses(startPort: port, endPort: port)
            if let process = processes.first {
                if AppSettings.shared.reservedPorts.contains(port) {
                    sendNotification(
                        title: "Reserved Port Threatened",
                        body: "Warning: Port \(port) is reserved but is now occupied by \(process.command) (PID: \(process.pid))",
                        identifier: "reserved-port-\(port)-threatened",
                        categoryIdentifier: Self.reservedPortCategoryIdentifier,
                        userInfo: ["port": port, "pid": process.pid]
                    )
                } else {
                    sendNotification(
                        title: "Port Occupied",
                        body: "Port \(port) is now in use by \(process.command) (PID: \(process.pid))",
                        identifier: "port-\(port)-occupied",
                        categoryIdentifier: Self.portOccupiedCategoryIdentifier,
                        userInfo: ["port": port, "pid": process.pid]
                    )
                }
            }
        } catch {
            sendNotification(
                title: "Port Occupied",
                body: "Port \(port) is now in use",
                identifier: "port-\(port)-occupied",
                categoryIdentifier: Self.portOccupiedCategoryIdentifier,
                userInfo: ["port": port]
            )
        }
    }

    func portWatcher(_ watcher: PortWatcher, didUpdateState state: PortState, forPort port: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.watchedPorts = self.portWatcher.getWatchedPorts()
        }
    }

    private func sendNotification(title: String, body: String, identifier: String, categoryIdentifier: String, userInfo: [String: Any] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = userInfo

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error)")
            }
        }
    }

    // MARK: - Connection Alert Notifications

    func sendConnectionAlertNotification(
        blocklistedCount: Int,
        suspiciousProcesses: [(processName: String, connectionCount: Int)]
    ) {
        guard notificationsEnabled else { return }

        var title: String
        var body: String

        if blocklistedCount > 0 && suspiciousProcesses.isEmpty {
            title = "Blocklisted Connections Detected"
            body = "\(blocklistedCount) connection(s) from blocklisted hosts have been detected"
        } else if blocklistedCount > 0 {
            title = "Security Alert"
            body = "\(blocklistedCount) blocklisted host match(es) + \(suspiciousProcesses.count) suspicious process(es) detected"
        } else if suspiciousProcesses.count == 1 {
            title = "Bot Activity Suspected"
            body = "\(suspiciousProcesses[0].processName) has \(suspiciousProcesses[0].connectionCount) connections - possible bot"
        } else if suspiciousProcesses.count > 1 {
            title = "Bot Activity Suspected"
            body = "\(suspiciousProcesses.count) processes with 50+ connections each - possible bot activity"
        } else {
            return
        }

        sendNotification(
            title: title,
            body: body,
            identifier: "connection-alert-\(UUID().uuidString)",
            categoryIdentifier: Self.connectionAlertCategoryIdentifier,
            userInfo: [
                "blocklistedCount": blocklistedCount,
                "suspiciousProcesses": suspiciousProcesses.map { ["processName": $0.processName, "count": $0.connectionCount] }
            ]
        )
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
