import SwiftUI
import AppKit
import UserNotifications
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

        guard let button = statusItem?.button else {
            print("MenuBarController: Failed to get status item button")
            return
        }

        // Create a professional menu bar icon programmatically
        let icon = createMenuBarIcon()
        button.image = icon
        button.image?.isTemplate = true // Ensures proper light/dark mode adaptation

        button.action = #selector(togglePanel)
        button.target = self

        // Global event monitor for outside-click dismiss
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissPanel()
        }
    }

    /// Create a crisp 18x18 menu bar icon showing a stylized port/network symbol
    private func createMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // Use SF Symbol for clean rendering
            guard let symbolImage = NSImage(systemSymbolName: "network.badge.shield.half.filled", accessibilityDescription: "PortPilot") else {
                // Fallback: draw a custom port icon
                self.drawCustomPortIcon(in: rect)
                return true
            }

            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            if let configured = symbolImage.withSymbolConfiguration(config) {
                configured.draw(in: rect)
            } else {
                symbolImage.draw(in: rect)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private func drawCustomPortIcon(in rect: NSRect) {
        let color = NSColor.black // Will be tinted by template mode
        color.setStroke()
        color.setFill()

        let lineWidth: CGFloat = 1.5

        // Draw a circle (representing a port)
        let circlePath = NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4))
        circlePath.lineWidth = lineWidth
        circlePath.stroke()

        // Draw center dot
        let centerDot = NSBezierPath(ovalIn: NSRect(
            x: rect.midX - 2, y: rect.midY - 2, width: 4, height: 4
        ))
        centerDot.fill()

        // Draw small lines radiating out (like a port symbol)
        let positions: [(CGFloat, CGFloat)] = [
            (rect.midX, rect.maxY - 2),  // top
            (rect.midX, rect.minY + 2),  // bottom
            (rect.minX + 2, rect.midY),  // left
            (rect.maxX - 2, rect.midY),  // right
        ]

        for (x, y) in positions {
            let dot = NSBezierPath(ovalIn: NSRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3))
            dot.fill()
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
        Task { @MainActor in
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.openSettingsWindow()
            }
        }
    }

    private func openSponsors() {
        dismissPanel()
        if let url = URL(string: "https://github.com/sponsors/sriinnu") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor func openMainWindow() {
        dismissPanel()
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
    }

    @MainActor func showPopover() {
        if !isPanelShown {
            showPanel()
        }
    }

    @MainActor func updateMenuBarIcon(activePorts: Int) {
        guard let button = statusItem?.button else { return }

        if activePorts > 0 {
            // Show port count as badge
            let icon = createMenuBarIconWithBadge(count: activePorts)
            button.image = icon
            button.image?.isTemplate = true
        } else {
            let icon = createMenuBarIcon()
            button.image = icon
            button.image?.isTemplate = true
        }
    }

    private func createMenuBarIconWithBadge(count: Int) -> NSImage {
        let size = NSSize(width: 30, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // Draw the base icon on the left
            let iconRect = NSRect(x: 0, y: 0, width: 18, height: 18)
            if let symbolImage = NSImage(systemSymbolName: "network.badge.shield.half.filled", accessibilityDescription: "PortPilot") {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                if let configured = symbolImage.withSymbolConfiguration(config) {
                    configured.draw(in: iconRect)
                }
            } else {
                self.drawCustomPortIcon(in: iconRect)
            }

            // Draw count text
            let countStr = count > 99 ? "99+" : "\(count)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .bold),
                .foregroundColor: NSColor.black // template mode handles color
            ]
            let textSize = countStr.size(withAttributes: attrs)
            let textRect = NSRect(
                x: 20 - textSize.width / 2,
                y: rect.midY - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            )
            countStr.draw(in: textRect, withAttributes: attrs)

            return true
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

    // Notification category identifiers
    static let portOccupiedCategoryIdentifier = "PORT_OCCUPIED"
    static let portAvailableCategoryIdentifier = "PORT_AVAILABLE"
    static let reservedPortCategoryIdentifier = "RESERVED_PORT"

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

        // Kill action
        let killAction = UNNotificationAction(
            identifier: Self.killActionIdentifier,
            title: "Kill",
            options: [.destructive, .authenticationRequired]
        )

        // Copy port action
        let copyPortAction = UNNotificationAction(
            identifier: Self.copyPortActionIdentifier,
            title: "Copy Port",
            options: [.foreground]
        )

        // Dismiss action
        let dismissAction = UNNotificationAction(
            identifier: Self.dismissActionIdentifier,
            title: "Dismiss",
            options: [.destructive]
        )

        // Port occupied category
        let portOccupiedCategory = UNNotificationCategory(
            identifier: Self.portOccupiedCategoryIdentifier,
            actions: [killAction, copyPortAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Port available category
        let portAvailableCategory = UNNotificationCategory(
            identifier: Self.portAvailableCategoryIdentifier,
            actions: [copyPortAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Reserved port category
        let reservedPortCategory = UNNotificationCategory(
            identifier: Self.reservedPortCategoryIdentifier,
            actions: [killAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        center.setNotificationCategories([portOccupiedCategory, portAvailableCategory, reservedPortCategory])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let port = userInfo["port"] as? Int ?? 0
        let identifier = response.actionIdentifier

        switch identifier {
        case Self.killActionIdentifier:
            // Kill the process on the port
            Task {
                try? portManager.killProcessOnPort(port, force: true)
            }
        case Self.copyPortActionIdentifier:
            // Copy port to clipboard
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(String(port), forType: .string)
        case Self.dismissActionIdentifier:
            // Just dismiss
            break
        default:
            break
        }

        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
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
                // Check if this is a reserved port
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
        watchedPorts = portWatcher.getWatchedPorts()
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
