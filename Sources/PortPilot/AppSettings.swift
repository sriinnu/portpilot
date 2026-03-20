import Foundation
import Combine
import AppKit
import SwiftUI

// MARK: - Appearance Mode
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }
}

// MARK: - Custom Program
struct CustomProgram: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var processNames: [String]
    var icon: String
    var colorHex: String

    var color: Color {
        Color(hex: colorHex) ?? .accentColor
    }

    init(id: UUID = UUID(), name: String, processNames: [String], icon: String = "app.fill", colorHex: String = "#007AFF") {
        self.id = id
        self.name = name
        self.processNames = processNames
        self.icon = icon
        self.colorHex = colorHex
    }
}

// MARK: - Color Hex Extension
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - App Settings
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // Keys
    private enum Keys {
        static let showDockIcon = "ShowDockIcon"
        static let showMenuBarIcon = "ShowMenuBarIcon"
        static let launchAtLogin = "LaunchAtLogin"
        static let showNotifications = "ShowNotifications"
        static let backgroundMonitoring = "BackgroundMonitoring"
        static let autoRefreshInterval = "AutoRefreshInterval"
        static let autoRefresh = "autoRefresh"
        static let refreshInterval = "refreshInterval"
        static let confirmBeforeKill = "confirmBeforeKill"
        static let defaultForceKill = "defaultForceKill"
        static let appearanceMode = "AppearanceMode"
        static let reservedPorts = "ReservedPorts"
        static let customPrograms = "CustomPrograms"
    }

    // Published properties
    @Published var showDockIcon: Bool {
        didSet {
            defaults.set(showDockIcon, forKey: Keys.showDockIcon)
            applyDockIconPolicy()
        }
    }

    @Published var showMenuBarIcon: Bool {
        didSet {
            defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon)
            NotificationCenter.default.post(name: .menuBarIconVisibilityChanged, object: showMenuBarIcon)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        }
    }

    @Published var showNotifications: Bool {
        didSet {
            defaults.set(showNotifications, forKey: Keys.showNotifications)
            NotificationManager.shared.notificationsEnabled = showNotifications
        }
    }

    @Published var backgroundMonitoring: Bool {
        didSet {
            defaults.set(backgroundMonitoring, forKey: Keys.backgroundMonitoring)
            if backgroundMonitoring {
                NotificationManager.shared.startWatching()
            } else {
                NotificationManager.shared.stopWatching()
            }
        }
    }

    @Published var autoRefreshInterval: Int {
        didSet {
            defaults.set(autoRefreshInterval, forKey: Keys.autoRefreshInterval)
            NotificationCenter.default.post(name: .autoRefreshIntervalChanged, object: autoRefreshInterval)
        }
    }

    @Published var autoRefresh: Bool {
        didSet {
            defaults.set(autoRefresh, forKey: Keys.autoRefresh)
            NotificationCenter.default.post(name: .autoRefreshChanged, object: autoRefresh)
        }
    }

    @Published var refreshInterval: Int {
        didSet {
            defaults.set(refreshInterval, forKey: Keys.refreshInterval)
            NotificationCenter.default.post(name: .autoRefreshChanged, object: nil)
        }
    }

    @Published var confirmBeforeKill: Bool {
        didSet {
            defaults.set(confirmBeforeKill, forKey: Keys.confirmBeforeKill)
        }
    }

    @Published var defaultForceKill: Bool {
        didSet {
            defaults.set(defaultForceKill, forKey: Keys.defaultForceKill)
        }
    }

    @Published var appearanceMode: AppearanceMode {
        didSet {
            defaults.set(appearanceMode.rawValue, forKey: Keys.appearanceMode)
            applyAppearance()
        }
    }

    @Published var reservedPorts: [Int] {
        didSet {
            defaults.set(reservedPorts, forKey: Keys.reservedPorts)
        }
    }

    @Published var customPrograms: [CustomProgram] {
        didSet {
            saveCustomPrograms()
        }
    }

    private init() {
        self.showDockIcon = defaults.object(forKey: Keys.showDockIcon) as? Bool ?? true
        self.showMenuBarIcon = defaults.object(forKey: Keys.showMenuBarIcon) as? Bool ?? true
        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        self.showNotifications = defaults.object(forKey: Keys.showNotifications) as? Bool ?? true
        self.backgroundMonitoring = defaults.object(forKey: Keys.backgroundMonitoring) as? Bool ?? false
        self.autoRefreshInterval = defaults.object(forKey: Keys.autoRefreshInterval) as? Int ?? 5
        self.autoRefresh = defaults.object(forKey: Keys.autoRefresh) as? Bool ?? false
        self.refreshInterval = defaults.object(forKey: Keys.refreshInterval) as? Int ?? 30
        self.confirmBeforeKill = defaults.object(forKey: Keys.confirmBeforeKill) as? Bool ?? true
        self.defaultForceKill = defaults.object(forKey: Keys.defaultForceKill) as? Bool ?? false

        let modeString = defaults.string(forKey: Keys.appearanceMode) ?? "System"
        self.appearanceMode = AppearanceMode(rawValue: modeString) ?? .system

        self.reservedPorts = defaults.array(forKey: Keys.reservedPorts) as? [Int] ?? []

        self.customPrograms = Self.loadCustomPrograms()

        NotificationManager.shared.notificationsEnabled = showNotifications
    }

    // MARK: - Apply Actions

    func applyAppearance() {
        DispatchQueue.main.async {
            switch self.appearanceMode {
            case .system:
                NSApp.appearance = nil
            case .light:
                NSApp.appearance = NSAppearance(named: .aqua)
            case .dark:
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }

    func applyDockIconPolicy() {
        DispatchQueue.main.async {
            if self.showDockIcon {
                NSApp.setActivationPolicy(.regular)
            } else {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    /// Call on app launch to apply saved settings
    func applyAllOnLaunch() {
        applyAppearance()
        applyDockIconPolicy()
        if backgroundMonitoring {
            NotificationManager.shared.startWatching()
        }
    }

    // MARK: - Custom Programs Persistence

    private static func loadCustomPrograms() -> [CustomProgram] {
        guard let data = UserDefaults.standard.data(forKey: Keys.customPrograms) else {
            return defaultCustomPrograms()
        }
        do {
            return try JSONDecoder().decode([CustomProgram].self, from: data)
        } catch {
            print("Failed to decode custom programs: \(error)")
            return defaultCustomPrograms()
        }
    }

    private func saveCustomPrograms() {
        do {
            let data = try JSONEncoder().encode(customPrograms)
            UserDefaults.standard.set(data, forKey: Keys.customPrograms)
        } catch {
            print("Failed to encode custom programs: \(error)")
        }
    }

    private static func defaultCustomPrograms() -> [CustomProgram] {
        [
            CustomProgram(
                name: "PostgreSQL",
                processNames: ["postgres", "postmaster", "pg_ctl"],
                icon: "cylinder.fill",
                colorHex: "#336791"
            ),
            CustomProgram(
                name: "Redis",
                processNames: ["redis-server", "redis-cli", "redis-sentinel"],
                icon: "square.stack.3d.up.fill",
                colorHex: "#DC382D"
            ),
            CustomProgram(
                name: "MongoDB",
                processNames: ["mongod", "mongos"],
                icon: "leaf.fill",
                colorHex: "#47A248"
            ),
            CustomProgram(
                name: "Node.js",
                processNames: ["node", "node.exe"],
                icon: "chevron.left.forwardslash.chevron.right",
                colorHex: "#339933"
            ),
            CustomProgram(
                name: "Docker",
                processNames: ["docker", "dockerd", "containerd"],
                icon: "shippingbox.fill",
                colorHex: "#2496ED"
            ),
        ]
    }
}

// MARK: - Settings Notification Names
extension Notification.Name {
    static let menuBarIconVisibilityChanged = Notification.Name("menuBarIconVisibilityChanged")
    static let appPolicyChanged = Notification.Name("appPolicyChanged")
    static let autoRefreshIntervalChanged = Notification.Name("autoRefreshIntervalChanged")
    static let autoRefreshChanged = Notification.Name("autoRefreshChanged")
    static let setupMenuBar = Notification.Name("setupMenuBar")
}
