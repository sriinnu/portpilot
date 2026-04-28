import SwiftUI
import AppKit

enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case menuBar = "Menu Bar"
    case notifications = "Notifications"
    case reserved = "Reserved"
    case programs = "Programs"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general:
            return "gear"
        case .appearance:
            return "paintbrush"
        case .menuBar:
            return "menubar.rectangle"
        case .notifications:
            return "bell"
        case .reserved:
            return "lock.shield"
        case .programs:
            return "app.fill"
        case .about:
            return "info.circle"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var viewModel: PortViewModel
    @State private var selection: SettingsPane = .general

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider().opacity(0.3)
            settingsDetail(for: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 780, height: 560)
        .background(Theme.Surface.windowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func settingsDetail(for pane: SettingsPane) -> some View {
        switch pane {
        case .general:
            GeneralSettingsView()
        case .appearance:
            AppearanceSettingsView()
        case .menuBar:
            MenuBarSettingsView()
        case .notifications:
            NotificationsSettingsView()
        case .reserved:
            ReservedPortsSettingsView()
        case .programs:
            CustomProgramsSettingsView()
        case .about:
            AboutSettingsView()
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Branding header
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Theme.Liquid.headerIcon)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.Liquid.accentPurpleMuted))
                Text("Settings")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)

            VStack(spacing: 4) {
                ForEach(SettingsPane.allCases) { pane in
                    Button {
                        selection = pane
                    } label: {
                        SettingsSidebarRow(
                            pane: pane,
                            isSelected: selection == pane
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)

            // Version footer
            HStack(spacing: 4) {
                Text("PortPilot")
                    .font(.system(size: 10, weight: .medium))
                Text("by Sriinnu")
                    .font(.system(size: 10))
            }
            .foregroundColor(.secondary.opacity(0.6))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(
            minWidth: 220,
            idealWidth: 220,
            maxWidth: 220,
            minHeight: 0,
            idealHeight: nil,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(Theme.Surface.controlBackground)
    }
}

private struct SettingsSidebarRow: View {
    let pane: SettingsPane
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: pane.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? Theme.Liquid.accentPurple : .secondary)
                .frame(width: 20)

            Text(pane.rawValue)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))

            Spacer(minLength: 0)
        }
        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.75))
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Theme.Surface.selected : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Theme.Surface.groupedStroke : Color.clear, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Liquid Card Components

private struct LiquidCard<Content: View>: View {
    let title: String
    let icon: String
    var footer: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.Liquid.accentPurple)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }

            content

            if let footer = footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
                    .lineSpacing(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.Surface.groupedFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.Surface.groupedStroke, lineWidth: 0.5)
        )
    }
}

// MARK: - General Settings
struct GeneralSettingsView: View {
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                LiquidCard(title: "Refresh", icon: "arrow.clockwise", footer: "Auto-refresh periodically scans for new ports and connections.") {
                    Toggle("Auto-refresh ports", isOn: $appSettings.autoRefresh)
                        .font(.system(size: 13))

                    if appSettings.autoRefresh {
                        Picker("Refresh interval", selection: $appSettings.refreshInterval) {
                            Text("15 seconds").tag(15)
                            Text("30 seconds").tag(30)
                            Text("1 minute").tag(60)
                            Text("5 minutes").tag(300)
                        }
                        .font(.system(size: 13))
                    }
                }

                LiquidCard(title: "Behavior", icon: "hand.raised", footer: "Force kill sends SIGKILL instead of SIGTERM.") {
                    Toggle("Confirm before killing processes", isOn: $appSettings.confirmBeforeKill)
                        .font(.system(size: 13))
                    Toggle("Default to force kill", isOn: $appSettings.defaultForceKill)
                        .font(.system(size: 13))
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Appearance Settings
struct AppearanceSettingsView: View {
    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject private var fontManager = FontManager.shared
    @State private var fontApplyMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Appearance mode
                LiquidCard(title: "Appearance", icon: "circle.lefthalf.filled", footer: "Choose between Light, Dark, or follow the System appearance.") {
                    HStack(spacing: 16) {
                        AppearancePreviewCard(isDark: false, isActive: appSettings.appearanceMode == .system, label: "System")
                            .onTapGesture { appSettings.appearanceMode = .system }
                        AppearancePreviewCard(isDark: false, isActive: appSettings.appearanceMode == .light, label: "Light")
                            .onTapGesture { appSettings.appearanceMode = .light }
                        AppearancePreviewCard(isDark: true, isActive: appSettings.appearanceMode == .dark, label: "Dark")
                            .onTapGesture { appSettings.appearanceMode = .dark }
                    }
                }

                // Color Theme
                LiquidCard(title: "Color Theme", icon: "paintpalette", footer: "Each theme comes with a recommended font pairing.") {
                    // Top row: 3 themes
                    HStack(spacing: 10) {
                        ForEach(Array(VisualTheme.allCases.prefix(3)), id: \.self) { theme in
                            ThemePreviewCard(theme: theme, isActive: appSettings.visualTheme == theme)
                                .onTapGesture { appSettings.visualTheme = theme }
                        }
                    }
                    // Bottom row: 3 themes
                    HStack(spacing: 10) {
                        ForEach(Array(VisualTheme.allCases.suffix(3)), id: \.self) { theme in
                            ThemePreviewCard(theme: theme, isActive: appSettings.visualTheme == theme)
                                .onTapGesture { appSettings.visualTheme = theme }
                        }
                    }

                    HStack {
                        Button {
                            applyRecommendedFonts()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "textformat")
                                Text("Apply \(appSettings.visualTheme.rawValue) fonts")
                                    .font(.system(size: 11))
                            }
                        }
                        if let message = fontApplyMessage {
                            Text(message)
                                .font(.system(size: 10))
                                .foregroundColor(message.hasPrefix("Not") ? .orange : Theme.Status.connected)
                        }
                    }
                }

                // Icon Pack
                LiquidCard(title: "Icon Pack", icon: "square.grid.2x2", footer: "Filled gives more weight. Minimal keeps it lighter.") {
                    HStack(spacing: 14) {
                        ForEach(IconPack.allCases) { pack in
                            IconPackPreviewCard(iconPack: pack, isActive: appSettings.iconPack == pack)
                                .onTapGesture { appSettings.iconPack = pack }
                        }
                    }
                }

                // Fonts
                LiquidCard(title: "Fonts", icon: "textformat.size") {
                    Picker("UI Font", selection: $appSettings.selectedFont) {
                        ForEach(fontManager.availableFamilies, id: \.self) { family in
                            Text(family)
                                .font(family == "System Default" ? .system(size: 13) : .custom(family, size: 13))
                                .tag(family)
                        }
                    }
                    .font(.system(size: 13))

                    Picker("Mono Font", selection: $appSettings.selectedMonoFont) {
                        ForEach(fontManager.monospacedFamilies, id: \.self) { family in
                            Text(family)
                                .font(family == "System Monospaced" ? .system(size: 13, design: .monospaced) : .custom(family, size: 13))
                                .tag(family)
                        }
                    }
                    .font(.system(size: 13))

                    HStack {
                        Text("Size").font(.system(size: 13))
                        Spacer()
                        Slider(value: $appSettings.fontSize, in: 9...18, step: 1).frame(width: 140)
                        Text(verbatim: "\(Int(appSettings.fontSize))px")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    FontPreviewCard(uiFont: appSettings.selectedFont, monoFont: appSettings.selectedMonoFont, size: CGFloat(appSettings.fontSize))
                }
            }
            .padding(20)
        }
    }

    private func applyRecommendedFonts() {
        let theme = appSettings.visualTheme
        var applied: [String] = []
        var missing: [String] = []
        if fontManager.isFamilyAvailable(theme.recommendedFont) {
            appSettings.selectedFont = theme.recommendedFont; applied.append(theme.recommendedFont)
        } else { missing.append(theme.recommendedFont) }
        if fontManager.isFamilyAvailable(theme.recommendedMonoFont) {
            appSettings.selectedMonoFont = theme.recommendedMonoFont; applied.append(theme.recommendedMonoFont)
        } else { missing.append(theme.recommendedMonoFont) }
        fontApplyMessage = missing.isEmpty ? "Applied: \(applied.joined(separator: " + "))" : "Not installed: \(missing.joined(separator: ", "))"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { fontApplyMessage = nil }
    }
}

// MARK: - Appearance Preview Card
struct AppearancePreviewCard: View {
    let isDark: Bool
    let isActive: Bool
    var label: String = "Light"

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(isDark ? Color(white: 0.15) : Color(white: 0.95))
                .frame(width: 100, height: 60)
                .overlay(
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isDark ? Color(white: 0.25) : Color(white: 0.85))
                            .frame(height: 10)
                        HStack(spacing: 4) {
                            Circle().fill(Theme.Status.connected).frame(width: 5, height: 5)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(isDark ? Color(white: 0.3) : Color(white: 0.8))
                                .frame(height: 6)
                        }
                        HStack(spacing: 4) {
                            Circle().fill(Theme.Status.connected).frame(width: 5, height: 5)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(isDark ? Color(white: 0.3) : Color(white: 0.8))
                                .frame(height: 6)
                        }
                    }
                    .padding(6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
                )

            Text(label)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .primary : .secondary)
        }
    }
}

// MARK: - Theme Preview Card
struct ThemePreviewCard: View {
    let theme: VisualTheme
    let isActive: Bool

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 10)
                .fill(backgroundColor)
                .frame(width: 132, height: 76)
                .overlay(
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(accentColor)
                            .frame(height: 10)
                        HStack(spacing: 6) {
                            Circle().fill(primaryColor).frame(width: 8, height: 8)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(secondaryColor.opacity(0.85))
                                .frame(height: 8)
                        }
                        HStack(spacing: 6) {
                            Circle().fill(secondaryColor).frame(width: 8, height: 8)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(primaryColor.opacity(0.85))
                                .frame(height: 8)
                        }
                    }
                    .padding(8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isActive ? accentColor : Color.primary.opacity(0.08), lineWidth: isActive ? 2 : 1)
                )

            VStack(spacing: 2) {
                Text(theme.rawValue)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .primary : .secondary)
                Text(theme.subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var backgroundColor: Color {
        switch theme {
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
        }
    }

    private var accentColor: Color {
        switch theme {
        case .classic:    return Color(red: 0.20, green: 0.45, blue: 0.90)
        case .graphite:   return Color(red: 0.26, green: 0.45, blue: 0.72)
        case .sunset:     return Color(red: 0.86, green: 0.40, blue: 0.30)
        case .oceanic:    return Color(red: 0.12, green: 0.46, blue: 0.72)
        case .noir:       return Color(white: 0.90)
        case .retro:      return Color(red: 0.65, green: 0.42, blue: 0.18)
        case .terminal:   return Color(red: 0.20, green: 1.00, blue: 0.36)
        case .paperwhite: return Color(red: 0.00, green: 0.40, blue: 1.00)
        case .synthwave:  return Color(red: 1.00, green: 0.30, blue: 0.78)
        case .solarized:  return Color(red: 0.16, green: 0.63, blue: 0.60)
        }
    }

    private var primaryColor: Color {
        switch theme {
        case .classic:    return Color(red: 0.20, green: 0.68, blue: 0.30)
        case .graphite:   return Color(red: 0.24, green: 0.64, blue: 0.48)
        case .sunset:     return Color(red: 0.92, green: 0.56, blue: 0.24)
        case .oceanic:    return Color(red: 0.12, green: 0.62, blue: 0.52)
        case .noir:       return Color(white: 0.75)
        case .retro:      return Color(red: 0.38, green: 0.55, blue: 0.28)
        case .terminal:   return Color(red: 0.20, green: 1.00, blue: 0.36)
        case .paperwhite: return Color(red: 0.18, green: 0.70, blue: 0.32)
        case .synthwave:  return Color(red: 0.00, green: 0.94, blue: 1.00)
        case .solarized:  return Color(red: 0.52, green: 0.60, blue: 0.00)
        }
    }

    private var secondaryColor: Color {
        switch theme {
        case .classic:    return Color(red: 0.55, green: 0.30, blue: 0.75)
        case .graphite:   return Color(red: 0.36, green: 0.42, blue: 0.70)
        case .sunset:     return Color(red: 0.62, green: 0.34, blue: 0.66)
        case .oceanic:    return Color(red: 0.36, green: 0.32, blue: 0.68)
        case .noir:       return Color(white: 0.50)
        case .retro:      return Color(red: 0.52, green: 0.35, blue: 0.55)
        case .terminal:   return Color(red: 1.00, green: 0.78, blue: 0.20)
        case .paperwhite: return Color(red: 1.00, green: 0.58, blue: 0.00)
        case .synthwave:  return Color(red: 0.72, green: 0.48, blue: 1.00)
        case .solarized:  return Color(red: 0.71, green: 0.54, blue: 0.00)
        }
    }
}

// MARK: - Icon Pack Preview Card
struct IconPackPreviewCard: View {
    let iconPack: IconPack
    let isActive: Bool

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.Surface.controlBackground)
                .frame(width: 132, height: 76)
                .overlay(
                    HStack(spacing: 12) {
                        Image(systemName: symbol("network.badge.shield.half.filled", "network"))
                        Image(systemName: symbol("cylinder.fill", "cylinder"))
                        Image(systemName: symbol("shippingbox.fill", "shippingbox"))
                    }
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LinearGradient(
                        colors: [Theme.Action.treeView, Theme.Section.kubernetes],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isActive ? Theme.Action.treeView : Color.primary.opacity(0.08), lineWidth: isActive ? 2 : 1)
                )

            Text(iconPack.rawValue)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .primary : .secondary)
        }
    }

    private func symbol(_ filled: String, _ minimal: String) -> String {
        switch iconPack {
        case .filled:
            return filled
        case .minimal:
            return minimal
        }
    }
}

// MARK: - Font Preview Card
struct FontPreviewCard: View {
    let uiFont: String
    let monoFont: String
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Theme.Surface.controlBackground)
            .frame(maxWidth: .infinity)
            .frame(height: 90)
            .overlay(
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle().fill(Theme.Status.connected).frame(width: 6, height: 6)
                        Text(":3000")
                            .font(monoFont == "System Monospaced"
                                  ? .system(size: size, weight: .semibold, design: .monospaced)
                                  : .custom(monoFont, size: size).weight(.semibold))
                        Text("TCP")
                            .font(.system(size: size - 3, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(3)
                        Text("node")
                            .font(uiFont == "System Default"
                                  ? .system(size: size)
                                  : .custom(uiFont, size: size))
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 8) {
                        Circle().fill(Theme.Status.warning).frame(width: 6, height: 6)
                        Text(":5432")
                            .font(monoFont == "System Monospaced"
                                  ? .system(size: size, weight: .semibold, design: .monospaced)
                                  : .custom(monoFont, size: size).weight(.semibold))
                        Text("TCP")
                            .font(.system(size: size - 3, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(3)
                        Text("postgres")
                            .font(uiFont == "System Default"
                                  ? .system(size: size)
                                  : .custom(uiFont, size: size))
                            .foregroundColor(.secondary)
                    }
                    Text("The quick brown fox jumps over the lazy dog")
                        .font(uiFont == "System Default"
                              ? .system(size: size - 1)
                              : .custom(uiFont, size: size - 1))
                        .foregroundColor(.secondary)
                }
                .padding(12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

// MARK: - Menu Bar Settings
struct MenuBarSettingsView: View {
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                LiquidCard(title: "Visibility", icon: "menubar.rectangle", footer: appSettings.showDockIcon || appSettings.showMenuBarIcon ? "The app stays running in the background when menu bar icon is shown." : nil) {
                    Toggle("Show menu bar icon", isOn: $appSettings.showMenuBarIcon).font(.system(size: 13))
                    Toggle("Show dock icon", isOn: $appSettings.showDockIcon).font(.system(size: 13))

                    if appSettings.showMenuBarIcon {
                        Toggle("Launch at login", isOn: $appSettings.launchAtLogin).font(.system(size: 13))
                    }

                    if !appSettings.showDockIcon && !appSettings.showMenuBarIcon {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Theme.Status.warning)
                            Text("Both icons hidden. You may not be able to access the app.")
                                .font(.system(size: 11)).foregroundColor(Theme.Status.warning)
                        }
                    }

                    Button { openTUI() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "terminal").font(.system(size: 12))
                            Text("Open TUI").font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.bordered)
                }

                LiquidCard(title: "Menu Bar Popover", icon: "clock", footer: "How often to refresh when the popover is open.") {
                    Picker("Auto-refresh interval", selection: $appSettings.autoRefreshInterval) {
                        Text("5 seconds").tag(5)
                        Text("10 seconds").tag(10)
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                    }
                    .font(.system(size: 13))
                }
            }
            .padding(20)
        }
    }

    private func openTUI() {
        // Find the TUI binary path
        let bundlePath = Bundle.main.bundlePath
        let tuiPath = bundlePath + "/../Resources/portpilot-tui"

        // Try to find it in common locations
        let possiblePaths = [
            bundlePath + "/../Resources/portpilot-tui",
            "/Applications/PortPilot.app/Contents/Resources/portpilot-tui",
            bundlePath + "/../../../../.build/release/portpilot-tui"
        ]

        var finalPath: String?
        for path in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                finalPath = path
                break
            }
        }

        // Fallback: use the built TUI path
        if finalPath == nil {
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            let builtTui = homeDir + "/Sriinnu/Personal/ports/.build/release/portpilot-tui"
            if FileManager.default.isExecutableFile(atPath: builtTui) {
                finalPath = builtTui
            }
        }

        guard let path = finalPath else {
            print("Could not find portpilot-tui binary")
            return
        }

        // Open Terminal.app and run the TUI
        let script = """
        tell application "Terminal"
            activate
            do script "\(path)"
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(nil)
        }
    }
}

// MARK: - Notifications Settings
struct NotificationsSettingsView: View {
    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject private var notificationManager = NotificationManager.shared
    @State private var newWatchPort: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                LiquidCard(title: "Notifications", icon: "bell") {
                    Toggle("Enable notifications", isOn: $appSettings.showNotifications).font(.system(size: 13))
                    Toggle("Background monitoring", isOn: $appSettings.backgroundMonitoring).font(.system(size: 13))
                }

                LiquidCard(title: "Port Monitoring", icon: "antenna.radiowaves.left.and.right", footer: "Port monitoring runs in the background when enabled.") {
                    Toggle(isOn: Binding(
                        get: { notificationManager.isWatching },
                        set: { _ in notificationManager.toggleWatching() }
                    )) {
                        HStack(spacing: 6) {
                            Image(systemName: notificationManager.isWatching ? Theme.Icon.connected : "antenna.slash")
                                .foregroundColor(notificationManager.isWatching ? Theme.Status.connected : .secondary)
                            Text(notificationManager.isWatching ? "Monitoring Active" : "Monitoring Paused")
                                .font(.system(size: 13))
                        }
                    }
                }

                LiquidCard(title: "Watched Ports", icon: "eye", footer: "You'll receive notifications when these ports change state.") {
                    HStack {
                        TextField("Port number", text: $newWatchPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Button("Add") {
                            if let port = Int(newWatchPort), port > 0, port <= 65535 {
                                notificationManager.addWatchedPort(port)
                                newWatchPort = ""
                            }
                        }
                        .disabled(newWatchPort.isEmpty || Int(newWatchPort) == nil)
                    }

                    if !notificationManager.watchedPorts.isEmpty {
                        ForEach(notificationManager.watchedPorts, id: \.port) { watched in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(watched.lastKnownState == .available ? Theme.Status.connected : (watched.lastKnownState == .occupied ? Theme.Status.error : Color.gray))
                                    .frame(width: 8, height: 8)
                                Text(verbatim: "Port \(watched.port)")
                                    .font(.system(size: 13, design: .monospaced))
                                Spacer()
                                Text(watched.lastKnownState == .available ? "Available" : (watched.lastKnownState == .occupied ? "Occupied" : "Unknown"))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Button { notificationManager.removeWatchedPort(watched.port) } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Reserved Ports Settings
struct ReservedPortsSettingsView: View {
    @ObservedObject private var appSettings = AppSettings.shared
    @EnvironmentObject var viewModel: PortViewModel
    @State private var newReservedPort: String = ""
    @State private var showWarning: Bool = false
    @State private var warningMessage: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                LiquidCard(title: "Reserved Ports", icon: "lock.shield", footer: "Reserved ports are protected from accidental kills. Add ports that should stay protected.") {
                    HStack {
                        TextField("Port number", text: $newReservedPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Button("Add") {
                            if let port = Int(newReservedPort), port > 0, port <= 65535 {
                                if !appSettings.reservedPorts.contains(port) {
                                    appSettings.reservedPorts.append(port)
                                    appSettings.reservedPorts.sort()
                                    newReservedPort = ""
                                }
                            }
                        }
                        .disabled(newReservedPort.isEmpty || Int(newReservedPort) == nil)
                    }

                    if !appSettings.reservedPorts.isEmpty {
                        ForEach(appSettings.reservedPorts, id: \.self) { port in
                            HStack(spacing: 8) {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundColor(Theme.Status.warning)
                                    .font(.system(size: 12))
                                Text(verbatim: "Port \(port)")
                                    .font(.system(size: 12, design: .monospaced))
                                Spacer()
                                if let process = viewModel.ports.first(where: { $0.port == port }) {
                                    Text(verbatim: "Occupied by \(process.command)")
                                        .font(.system(size: 10))
                                        .foregroundColor(Theme.Status.error)
                                } else {
                                    Text("Available")
                                        .font(.system(size: 10))
                                        .foregroundColor(Theme.Status.connected)
                                }
                                Button { appSettings.reservedPorts.removeAll { $0 == port } } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    } else {
                        Text("No reserved ports configured")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                    }
                }

                LiquidCard(title: "Status", icon: "checkmark.shield") {
                    Button("Check Reserved Ports") {
                        let threatened = viewModel.checkReservedPorts()
                        if threatened.isEmpty {
                            warningMessage = "All reserved ports are available."
                        } else {
                            let descriptions = threatened.map { "Port \($0.port): \($0.occupant)" }.joined(separator: "\n")
                            warningMessage = "Warning:\n\(descriptions)"
                        }
                        showWarning = true
                    }
                }
            }
            .padding(20)
        }
        .alert("Reserved Ports Status", isPresented: $showWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(warningMessage)
        }
    }
}

// MARK: - Custom Programs Settings
struct CustomProgramsSettingsView: View {
    @ObservedObject private var appSettings = AppSettings.shared

    @State private var editingProgram: CustomProgram?
    @State private var isAddingNew: Bool = false
    @State private var newProgramName: String = ""
    @State private var newProcessNames: String = ""
    @State private var newIcon: String = "app.fill"
    @State private var newColorHex: String = "#007AFF"
    @State private var runningCounts: [UUID: Int] = [:]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                LiquidCard(title: "Custom Programs", icon: "app.fill", footer: "Track all PIDs for a program by its process name(s).") {
                    if appSettings.customPrograms.isEmpty {
                        Text("No custom programs configured")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                    } else {
                        ForEach(appSettings.customPrograms) { program in
                            HStack(spacing: 10) {
                                Image(systemName: program.icon)
                                    .font(.system(size: 14))
                                    .foregroundColor(program.color)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(program.name).font(.system(size: 13, weight: .medium))
                                    Text(program.processNames.joined(separator: ", "))
                                        .font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                                }

                                Spacer()

                                if let count = runningCounts[program.id], count > 0 {
                                    Text(verbatim: "\(count) running")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(Theme.Status.connected)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Theme.Badge.connectedBackground)
                                        .cornerRadius(4)
                                }

                                Button {
                                    editingProgram = program
                                    newProgramName = program.name
                                    newProcessNames = program.processNames.joined(separator: ", ")
                                    newIcon = program.icon
                                    newColorHex = program.colorHex
                                    isAddingNew = false
                                } label: {
                                    Image(systemName: "pencil").font(.system(size: 11))
                                }
                                .buttonStyle(.borderless)

                                Button {
                                    appSettings.customPrograms.removeAll { $0.id == program.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundColor(Theme.Status.error)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }

                    // Add new program button
                    Button {
                        isAddingNew = true
                        newProgramName = ""
                        newProcessNames = ""
                        newIcon = "app.fill"
                        newColorHex = "#007AFF"
                        editingProgram = CustomProgram(name: "", processNames: [])
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.Liquid.accentPurple)
                            Text("Add Program")
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(20)
        }
        .task(id: appSettings.customPrograms.map(\.id).map(\.uuidString).joined(separator: ",")) {
            refreshRunningCounts()
        }
        .sheet(item: $editingProgram) { program in
            CustomProgramEditorView(
                program: program,
                isNew: isAddingNew,
                onSave: { name, processNames, icon, colorHex in
                    if isAddingNew {
                        let newProgram = CustomProgram(
                            name: name,
                            processNames: processNames,
                            icon: icon,
                            colorHex: colorHex
                        )
                        appSettings.customPrograms.append(newProgram)
                    } else {
                        if let index = appSettings.customPrograms.firstIndex(where: { $0.id == program.id }) {
                            appSettings.customPrograms[index].name = name
                            appSettings.customPrograms[index].processNames = processNames
                            appSettings.customPrograms[index].icon = icon
                            appSettings.customPrograms[index].colorHex = colorHex
                        }
                    }
                    editingProgram = nil
                },
                onCancel: {
                    editingProgram = nil
                }
            )
        }
    }

    private func refreshRunningCounts() {
        let programs = appSettings.customPrograms
        Task.detached(priority: .utility) {
            var counts: [UUID: Int] = [:]
            let portManager = PortManager()

            for program in programs {
                counts[program.id] = portManager.getProcessesByName(names: program.processNames).count
            }

            let snapshot = counts
            await MainActor.run {
                runningCounts = snapshot
            }
        }
    }
}

// MARK: - Custom Program Editor View
struct CustomProgramEditorView: View {
    let program: CustomProgram?
    let isNew: Bool
    let onSave: (String, [String], String, String) -> Void
    let onCancel: () -> Void

    @State private var programName: String = ""
    @State private var processNames: String = ""
    @State private var selectedIcon: String = "app.fill"
    @State private var selectedColor: String = "#007AFF"

    private let availableIcons = [
        "app.fill", "desktopcomputer", "server.rack", "cylinder.fill",
        "square.stack.3d.up.fill", "leaf.fill", "chevron.left.forwardslash.chevron.right",
        "shippingbox.fill", "film", "music.note", "gamecontroller.fill",
        "brackets.curl", "terminal.fill", "hammer.fill", "wrench.and.screwdriver.fill"
    ]

    private let availableColors = [
        "#007AFF", "#34C759", "#FF9500", "#FF3B30",
        "#5856D6", "#AF52DE", "#00C7BE", "#FF2D55",
        "#336791", "#DC382D", "#47A248", "#2496ED"
    ]

    var body: some View {
        VStack(spacing: 20) {
            Text(isNew ? "Add Custom Program" : "Edit Custom Program")
                .font(.headline)

            Form {
                Section {
                    TextField("Program Name", text: $programName)
                        .textFieldStyle(.roundedBorder)

                    TextField("Process Names (comma-separated)", text: $processNames)
                        .textFieldStyle(.roundedBorder)
                        .help("e.g., postgres, postmaster, pg_ctl")

                    Text("Separate multiple process names with commas. All PIDs matching these names will be tracked.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Program Details")
                }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], spacing: 12) {
                        ForEach(availableIcons, id: \.self) { icon in
                            Button(action: { selectedIcon = icon }) {
                                Image(systemName: icon)
                                    .font(.system(size: 20))
                                    .frame(width: 36, height: 36)
                                    .background(selectedIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Icon")
                }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], spacing: 8) {
                        ForEach(availableColors, id: \.self) { color in
                            Button(action: { selectedColor = color }) {
                                Circle()
                                    .fill(Color(hex: color) ?? .blue)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(selectedColor == color ? Color.primary : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Color")
                }
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let names = processNames.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    onSave(programName, names, selectedIcon, selectedColor)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(programName.isEmpty || processNames.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 480)
        .onAppear {
            if let program = program {
                programName = program.name
                processNames = program.processNames.joined(separator: ", ")
                selectedIcon = program.icon
                selectedColor = program.colorHex
            }
        }
    }
}

// MARK: - About Settings
struct AboutSettingsView: View {
    private var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0"
    }

    private var buildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? shortVersion
    }

    private var copyrightText: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "Copyright \u{00A9} 2024\u{2013}2026 Srinivas Pendela. All rights reserved."
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // App icon
            Image(systemName: "globe")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.Liquid.accentPurple, Theme.Section.kubernetes],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 80, height: 80)
                .background(
                    Circle()
                        .fill(Theme.Liquid.accentPurpleMuted)
                )

            VStack(spacing: 6) {
                Text("PortPilot")
                    .font(.system(size: 28, weight: .bold))

                Text("Version \(shortVersion)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                if buildVersion != shortVersion {
                    Text("Build \(buildVersion)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }

            // Author
            VStack(spacing: 4) {
                Text("Designed and built by")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("Srinivas Pendela")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Liquid.accentPurple)
            }
            .padding(.top, 4)

            // Sponsor button
            Button {
                if let url = URL(string: "https://github.com/sponsors/sriinnu") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12))
                    Text("Sponsor PortPilot")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Theme.Action.sponsors, Theme.Action.sponsors.opacity(0.8)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                )
            }
            .buttonStyle(.plain)
            .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
            .padding(.top, 4)

            Text(copyrightText)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

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
