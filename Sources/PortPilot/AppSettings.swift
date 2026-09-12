import Foundation
import Combine
import AppKit
import SwiftUI
import ServiceManagement

// MARK: - Appearance Mode
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }
}

// MARK: - Visual Theme
enum VisualTheme: String, CaseIterable, Identifiable {
    case classic = "Classic"
    case graphite = "Graphite"
    case sunset = "Sunset"
    case oceanic = "Oceanic"
    case noir = "Noir"
    case retro = "Retro"
    case terminal = "Terminal"
    case paperwhite = "Paperwhite"
    case synthwave = "Synthwave"
    case solarized = "Solarized"
    case nord = "Nord"
    case papercraft = "Papercraft"

    var id: String { rawValue }

    /// This theme's full color palette — the single source every theme
    /// lookup (and the settings preview card) derives from.
    var palette: ThemePalette {
        switch self {
        case .classic:    return .classic
        case .graphite:   return .graphite
        case .sunset:     return .sunset
        case .oceanic:    return .oceanic
        case .noir:       return .noir
        case .retro:      return .retro
        case .terminal:   return .terminal
        case .paperwhite: return .paperwhite
        case .synthwave:  return .synthwave
        case .solarized:  return .solarized
        case .nord:       return .nord
        case .papercraft: return .papercraft
        }
    }

    /// Themes whose character only lands on dark surfaces — picking one in
    /// Light appearance deserves a nudge, not silence.
    var isDarkNative: Bool {
        switch self {
        case .noir, .terminal, .synthwave: return true
        default: return false
        }
    }

    /// Recommended UI font for this theme
    var recommendedFont: String {
        switch self {
        case .classic: return "System Default"
        case .graphite: return "SF Pro"
        case .sunset: return "Avenir Next"
        case .oceanic: return "SF Pro Rounded"
        case .noir: return "Helvetica Neue"
        case .retro: return "American Typewriter"
        case .terminal: return "Menlo"
        case .paperwhite: return "Helvetica Neue"
        case .synthwave: return "Avenir Next"
        case .solarized: return "System Default"
        case .nord: return "Helvetica Neue"
        case .papercraft: return "Georgia"
        }
    }

    /// Recommended monospaced font for this theme
    var recommendedMonoFont: String {
        switch self {
        case .classic: return "System Monospaced"
        case .graphite: return "SF Mono"
        case .sunset: return "Menlo"
        case .oceanic: return "SF Mono"
        case .noir: return "Fira Code"
        case .retro: return "Courier New"
        case .terminal: return "Menlo"
        case .paperwhite: return "Menlo"
        case .synthwave: return "Menlo"
        case .solarized: return "Menlo"
        case .nord: return "Menlo"
        case .papercraft: return "Menlo"
        }
    }

    /// Short description of the theme's character
    var subtitle: String {
        switch self {
        case .classic: return "Vibrant and balanced"
        case .graphite: return "Calm and professional"
        case .sunset: return "Warm and expressive"
        case .oceanic: return "Deep and focused"
        case .noir: return "Sharp and minimal"
        case .retro: return "Warm and nostalgic"
        case .terminal: return "Phosphor green, CRT nights"
        case .paperwhite: return "Crisp white, editorial calm"
        case .synthwave: return "Magenta + cyan, late 1984"
        case .solarized: return "Developer classic, warm cream"
        case .nord: return "Polar blues, quiet and cold"
        case .papercraft: return "Layered paper strata at dusk"
        }
    }

    /// Idealized surface tone for the settings preview card. Everything
    /// else the card shows (accent, primary, secondary) comes live from
    /// `palette` — only the surface tone is curated per theme, since real
    /// surfaces are computed blends, not palette entries.
    var previewSurface: Color {
        switch self {
        case .classic:    return Color(white: 0.95)
        case .graphite:   return Color(red: 0.93, green: 0.94, blue: 0.96)
        case .sunset:     return Color(red: 0.98, green: 0.95, blue: 0.92)
        case .oceanic:    return Color(red: 0.90, green: 0.95, blue: 0.98)
        case .noir:       return Color(white: 0.18)
        case .retro:      return Color(red: 0.96, green: 0.93, blue: 0.88)
        case .terminal:   return Color(red: 0.06, green: 0.08, blue: 0.07)
        case .paperwhite: return Color(white: 0.99)
        case .synthwave:  return Color(red: 0.10, green: 0.07, blue: 0.20)
        case .solarized:  return Color(red: 0.99, green: 0.96, blue: 0.89)
        case .nord:       return Color(red: 0.91, green: 0.93, blue: 0.96)
        case .papercraft: return Color(red: 0.97, green: 0.93, blue: 0.85)  // warm craft cream
        }
    }
}

// MARK: - Icon Pack
enum IconPack: String, CaseIterable, Identifiable {
    case filled = "Filled"
    case minimal = "Minimal"

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
        static let visualTheme = "VisualTheme"
        static let iconPack = "IconPack"
        static let reservedPorts = "ReservedPorts"
        static let guardedPorts = "GuardedPorts"
        static let customPrograms = "CustomPrograms"
        static let selectedFont = "SelectedFont"
        static let selectedMonoFont = "SelectedMonoFont"
        static let fontSize = "FontSize"
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
            applyDockIconPolicy()
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            // SMAppService is the launch-at-login mechanism on macOS 13+.
            // The old version only wrote the flag — the toggle was a placebo.
            registerLaunchAtLogin(launchAtLogin)
        }
    }

    private func registerLaunchAtLogin(_ enabled: Bool) {
        Task.detached(priority: .userInitiated) {
            // Sync variants — already off the main thread, blocking here is fine.
            let service = SMAppService.mainApp
            do {
                if enabled {
                    if service.status == .notRegistered {
                        try service.register()
                    }
                } else {
                    if service.status != .notRegistered {
                        try service.unregister()
                    }
                }
            } catch {
                NSLog("Launch-at-login change failed: \(error.localizedDescription)")
            }
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
            // The popover-open refresh timer reads this on each panel open.
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

    @Published var visualTheme: VisualTheme {
        didSet {
            defaults.set(visualTheme.rawValue, forKey: Keys.visualTheme)
            refreshVisibleChrome()
        }
    }

    @Published var iconPack: IconPack {
        didSet {
            defaults.set(iconPack.rawValue, forKey: Keys.iconPack)
            refreshVisibleChrome()
        }
    }

    @Published var selectedFont: String {
        didSet {
            defaults.set(selectedFont, forKey: Keys.selectedFont)
            refreshVisibleChrome()
        }
    }

    @Published var selectedMonoFont: String {
        didSet {
            defaults.set(selectedMonoFont, forKey: Keys.selectedMonoFont)
            refreshVisibleChrome()
        }
    }

    @Published var fontSize: Double {
        didSet {
            defaults.set(fontSize, forKey: Keys.fontSize)
            refreshVisibleChrome()
        }
    }

    @Published var reservedPorts: [Int] {
        didSet {
            defaults.set(reservedPorts, forKey: Keys.reservedPorts)
        }
    }

    /// Ports under active guard: current holders are grandfathered, and
    /// anything that binds afterwards gets evicted. Owned/written by
    /// PortGuardStore — this property only persists the list.
    @Published var guardedPorts: [Int] {
        didSet {
            defaults.set(guardedPorts, forKey: Keys.guardedPorts)
        }
    }

    @Published var customPrograms: [CustomProgram] {
        didSet {
            saveCustomPrograms()
        }
    }

    private init() {
        self.showDockIcon = defaults.object(forKey: Keys.showDockIcon) as? Bool ?? false
        self.showMenuBarIcon = defaults.object(forKey: Keys.showMenuBarIcon) as? Bool ?? true
        // OS truth wins both ways: if the user removed PortPilot from Login
        // Items in System Settings, fix the flag instead of re-registering
        // over them — and if they added it there manually, the toggle should
        // show ON instead of pretending it's off. A pending-approval
        // registration keeps the stored flag.
        let storedLaunchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        let effectiveLaunchAtLogin: Bool
        switch SMAppService.mainApp.status {
        case .enabled:
            effectiveLaunchAtLogin = true
        case .requiresApproval:
            effectiveLaunchAtLogin = storedLaunchAtLogin
        default:
            effectiveLaunchAtLogin = false
        }
        self.launchAtLogin = effectiveLaunchAtLogin
        if storedLaunchAtLogin != effectiveLaunchAtLogin {
            defaults.set(effectiveLaunchAtLogin, forKey: Keys.launchAtLogin)
        }
        self.showNotifications = defaults.object(forKey: Keys.showNotifications) as? Bool ?? true
        self.backgroundMonitoring = defaults.object(forKey: Keys.backgroundMonitoring) as? Bool ?? false
        self.autoRefreshInterval = defaults.object(forKey: Keys.autoRefreshInterval) as? Int ?? 5
        self.autoRefresh = defaults.object(forKey: Keys.autoRefresh) as? Bool ?? false
        self.refreshInterval = defaults.object(forKey: Keys.refreshInterval) as? Int ?? 30
        self.confirmBeforeKill = defaults.object(forKey: Keys.confirmBeforeKill) as? Bool ?? true
        self.defaultForceKill = defaults.object(forKey: Keys.defaultForceKill) as? Bool ?? false

        let modeString = defaults.string(forKey: Keys.appearanceMode) ?? "System"
        self.appearanceMode = AppearanceMode(rawValue: modeString) ?? .system
        let visualThemeString = defaults.string(forKey: Keys.visualTheme) ?? VisualTheme.classic.rawValue
        self.visualTheme = VisualTheme(rawValue: visualThemeString) ?? .classic
        let iconPackString = defaults.string(forKey: Keys.iconPack) ?? IconPack.filled.rawValue
        self.iconPack = IconPack(rawValue: iconPackString) ?? .filled

        self.selectedFont = defaults.string(forKey: Keys.selectedFont) ?? "System Default"
        self.selectedMonoFont = defaults.string(forKey: Keys.selectedMonoFont) ?? "System Monospaced"
        self.fontSize = defaults.object(forKey: Keys.fontSize) as? Double ?? 12.0

        self.reservedPorts = defaults.array(forKey: Keys.reservedPorts) as? [Int] ?? []
        self.guardedPorts = defaults.array(forKey: Keys.guardedPorts) as? [Int] ?? []

        self.customPrograms = Self.loadCustomPrograms()

        NotificationManager.shared.notificationsEnabled = showNotifications
    }

    // MARK: - Apply Actions

    func applyAppearance() {
        DispatchQueue.main.async {
            let appearance: NSAppearance?
            switch self.appearanceMode {
            case .system:
                appearance = nil
            case .light:
                appearance = NSAppearance(named: .aqua)
            case .dark:
                appearance = NSAppearance(named: .darkAqua)
            }

            NSApp.appearance = appearance
            self.refreshVisibleChrome(using: appearance)
        }
    }

    func applyDockIconPolicy() {
        DispatchQueue.main.async {
            // I only surface the Dock icon when the menu bar icon is hidden.
            if self.showDockIcon && !self.showMenuBarIcon {
                NSApp.setActivationPolicy(.regular)
            } else {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    /// Call on app launch to apply saved settings
    func applyAllOnLaunch() {
        // Initialize FontManager first so custom fonts are available before appearance applies
        _ = FontManager.shared
        applyAppearance()
        applyDockIconPolicy()
        if backgroundMonitoring {
            NotificationManager.shared.startWatching()
        }
    }

    /// I refresh the visible chrome so theme and icon changes land immediately on existing windows.
    private func refreshVisibleChrome(using appearance: NSAppearance? = NSApp.appearance) {
        for window in NSApp.windows {
            window.appearance = appearance
            window.invalidateShadow()
            window.contentView?.needsLayout = true
            window.contentView?.needsDisplay = true
            if let menuBarPanel = window as? MenuBarPanel {
                menuBarPanel.refreshTheme()
            }
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
    static let autoRefreshChanged = Notification.Name("autoRefreshChanged")
    static let setupMenuBar = Notification.Name("setupMenuBar")
}
