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
            Divider()
            settingsDetail(for: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 780, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
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
            Text("Settings")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.top, 18)

            VStack(spacing: 6) {
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
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct SettingsSidebarRow: View {
    let pane: SettingsPane
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: pane.icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 18)

            Text(pane.rawValue)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))

            Spacer(minLength: 0)
        }
        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.88))
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.18) : Color.clear, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
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
                Picker("Appearance Mode", selection: $appSettings.appearanceMode) {
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
                    // System preview
                    AppearancePreviewCard(isDark: false, isActive: appSettings.appearanceMode == .system, label: "System")
                    // Light preview
                    AppearancePreviewCard(isDark: false, isActive: appSettings.appearanceMode == .light, label: "Light")
                    // Dark preview
                    AppearancePreviewCard(isDark: true, isActive: appSettings.appearanceMode == .dark, label: "Dark")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            } header: {
                Text("Preview")
            }

            Section {
                Picker("Color Theme", selection: $appSettings.visualTheme) {
                    ForEach(VisualTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }

                // Top row: 3 themes
                HStack(spacing: 10) {
                    ForEach(Array(VisualTheme.allCases.prefix(3)), id: \.self) { theme in
                        ThemePreviewCard(
                            theme: theme,
                            isActive: appSettings.visualTheme == theme
                        )
                        .onTapGesture { appSettings.visualTheme = theme }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)

                // Bottom row: 2 themes
                HStack(spacing: 10) {
                    ForEach(Array(VisualTheme.allCases.suffix(2)), id: \.self) { theme in
                        ThemePreviewCard(
                            theme: theme,
                            isActive: appSettings.visualTheme == theme
                        )
                        .onTapGesture { appSettings.visualTheme = theme }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)

                // Apply recommended fonts button
                HStack {
                    Button {
                        let theme = appSettings.visualTheme
                        var applied: [String] = []
                        var missing: [String] = []

                        if fontManager.isFamilyAvailable(theme.recommendedFont) {
                            appSettings.selectedFont = theme.recommendedFont
                            applied.append(theme.recommendedFont)
                        } else {
                            missing.append(theme.recommendedFont)
                        }
                        if fontManager.isFamilyAvailable(theme.recommendedMonoFont) {
                            appSettings.selectedMonoFont = theme.recommendedMonoFont
                            applied.append(theme.recommendedMonoFont)
                        } else {
                            missing.append(theme.recommendedMonoFont)
                        }

                        if !missing.isEmpty {
                            fontApplyMessage = "Not installed: \(missing.joined(separator: ", "))"
                        } else {
                            fontApplyMessage = "Applied: \(applied.joined(separator: " + "))"
                        }
                        // Clear message after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            fontApplyMessage = nil
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "textformat")
                            Text("Apply \(appSettings.visualTheme.rawValue) recommended fonts")
                                .font(.system(size: 11))
                        }
                    }
                    .help("Sets UI font to \(appSettings.visualTheme.recommendedFont) and mono font to \(appSettings.visualTheme.recommendedMonoFont)")

                    if let message = fontApplyMessage {
                        Text(message)
                            .font(.system(size: 10))
                            .foregroundColor(message.hasPrefix("Not") ? .orange : .green)
                            .transition(.opacity)
                    }
                }
            } header: {
                Text("Color Theme")
            } footer: {
                Text("Each theme comes with a recommended font pairing. Click the button above to apply it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Picker("Icon Pack", selection: $appSettings.iconPack) {
                    ForEach(IconPack.allCases) { pack in
                        Text(pack.rawValue).tag(pack)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 14) {
                    ForEach(IconPack.allCases) { pack in
                        IconPackPreviewCard(
                            iconPack: pack,
                            isActive: appSettings.iconPack == pack
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            } header: {
                Text("Icon Pack")
            } footer: {
                Text("Filled gives the app more weight. Minimal keeps the iconography lighter and cleaner.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // MARK: - Font Settings
            Section {
                Picker("UI Font", selection: $appSettings.selectedFont) {
                    ForEach(fontManager.availableFamilies, id: \.self) { family in
                        Text(family)
                            .font(family == "System Default"
                                  ? .system(size: 13)
                                  : .custom(family, size: 13))
                            .tag(family)
                    }
                }
                .onAppear {
                    if !fontManager.availableFamilies.contains(appSettings.selectedFont) {
                        appSettings.selectedFont = "System Default"
                    }
                }

                Picker("Monospaced Font", selection: $appSettings.selectedMonoFont) {
                    ForEach(fontManager.monospacedFamilies, id: \.self) { family in
                        Text(family)
                            .font(family == "System Monospaced"
                                  ? .system(size: 13, design: .monospaced)
                                  : .custom(family, size: 13))
                            .tag(family)
                    }
                }
                .onAppear {
                    if !fontManager.monospacedFamilies.contains(appSettings.selectedMonoFont) {
                        appSettings.selectedMonoFont = "System Monospaced"
                    }
                }

                HStack {
                    Text("Font Size")
                    Spacer()
                    Slider(value: $appSettings.fontSize, in: 9...18, step: 1)
                        .frame(width: 160)
                    Text("\(Int(appSettings.fontSize))px")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
            } header: {
                Text("Fonts")
            }

            Section {
                // Live font preview
                FontPreviewCard(
                    uiFont: appSettings.selectedFont,
                    monoFont: appSettings.selectedMonoFont,
                    size: CGFloat(appSettings.fontSize)
                )
                .padding(.vertical, 4)
            } header: {
                Text("Preview")
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Project Fonts")
                            .font(.system(size: 12, weight: .medium))
                        Text(fontManager.projectFontsURL.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Open") {
                        fontManager.revealFontsFolder()
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("User Fonts")
                            .font(.system(size: 12, weight: .medium))
                        Text(fontManager.appSupportFontsURL.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Open") {
                        fontManager.revealAppSupportFontsFolder()
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        fontManager.reload()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Reload Fonts")
                        }
                    }
                }

                if !fontManager.customFontFamilies.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Loaded custom fonts:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        ForEach(fontManager.customFontFamilies, id: \.self) { family in
                            Text("• \(family)")
                                .font(.custom(family, size: 12))
                        }
                    }
                }
            } header: {
                Text("Custom Fonts")
            } footer: {
                Text("Drop .ttf or .otf files into either folder and click Reload. The project Fonts/ folder lives next to your Sources/ directory.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ObservedObject private var fontManager = FontManager.shared
    @State private var fontApplyMessage: String?

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
        case .classic:
            return Color(white: 0.95)
        case .graphite:
            return Color(red: 0.93, green: 0.94, blue: 0.96)
        case .sunset:
            return Color(red: 0.98, green: 0.95, blue: 0.92)
        case .oceanic:
            return Color(red: 0.90, green: 0.95, blue: 0.98)
        case .noir:
            // Slightly lighter in context so the card is visible against dark mode backgrounds
            return Color(white: 0.18)
        }
    }

    private var accentColor: Color {
        switch theme {
        case .classic:
            return Color(red: 0.20, green: 0.45, blue: 0.90)
        case .graphite:
            return Color(red: 0.26, green: 0.45, blue: 0.72)
        case .sunset:
            return Color(red: 0.86, green: 0.40, blue: 0.30)
        case .oceanic:
            return Color(red: 0.12, green: 0.46, blue: 0.72)
        case .noir:
            return Color(white: 0.90)
        }
    }

    private var primaryColor: Color {
        switch theme {
        case .classic:
            return Color(red: 0.20, green: 0.68, blue: 0.30)
        case .graphite:
            return Color(red: 0.24, green: 0.64, blue: 0.48)
        case .sunset:
            return Color(red: 0.92, green: 0.56, blue: 0.24)
        case .oceanic:
            return Color(red: 0.12, green: 0.62, blue: 0.52)
        case .noir:
            return Color(white: 0.75)
        }
    }

    private var secondaryColor: Color {
        switch theme {
        case .classic:
            return Color(red: 0.55, green: 0.30, blue: 0.75)
        case .graphite:
            return Color(red: 0.36, green: 0.42, blue: 0.70)
        case .sunset:
            return Color(red: 0.62, green: 0.34, blue: 0.66)
        case .oceanic:
            return Color(red: 0.36, green: 0.32, blue: 0.68)
        case .noir:
            return Color(white: 0.50)
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
                .fill(Color(nsColor: .controlBackgroundColor))
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
            .fill(Color(nsColor: .controlBackgroundColor))
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
        Form {
            Section {
                Toggle("Show menu bar icon", isOn: $appSettings.showMenuBarIcon)
                    .help("Show or hide the PortPilot icon in the menu bar")

                Toggle("Show dock icon", isOn: $appSettings.showDockIcon)
                    .help("Show or hide the PortPilot icon in the Dock")

                if appSettings.showMenuBarIcon {
                    Toggle("Launch at login", isOn: $appSettings.launchAtLogin)
                        .help("Automatically start PortPilot when you log in")

                    Button {
                        openTUI()
                    } label: {
                        HStack {
                            Image(systemName: "terminal")
                            Text("Open TUI")
                        }
                    }
                    .buttonStyle(.bordered)
                    .help("Open the terminal-based user interface")
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
                Text("How often to refresh the port list when the menu bar popover is open. Appearance, color theme, and icon pack live in Settings > Appearance.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
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

// MARK: - Reserved Ports Settings
struct ReservedPortsSettingsView: View {
    @ObservedObject private var appSettings = AppSettings.shared
    @EnvironmentObject var viewModel: PortViewModel
    @State private var newReservedPort: String = ""
    @State private var showWarning: Bool = false
    @State private var warningMessage: String = ""

    var body: some View {
        Form {
            Section {
                Text("Reserved ports are protected from being accidentally killed. When a reserved port becomes occupied by an unknown process, you'll receive a warning notification.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("About Reserved Ports")
            }

            Section {
                HStack {
                    TextField("Port number", text: $newReservedPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Button("Add Port") {
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
                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(Theme.Status.warning)
                                .font(.system(size: 12))
                            Text("Port \(port)")
                                .font(.system(size: 12, design: .monospaced))
                            Spacer()

                            // Show warning if port is occupied
                            if let process = viewModel.ports.first(where: { $0.port == port }) {
                                Text("Occupied by \(process.command)")
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.Status.error)
                            } else {
                                Text("Available")
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.Status.connected)
                            }

                            Button(action: {
                                appSettings.reservedPorts.removeAll { $0 == port }
                            }) {
                                Image(systemName: Theme.Icon.clearSearch)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } else {
                    Text("No reserved ports configured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Reserved Ports")
            } footer: {
                Text("Add ports that should be protected. You can still manually kill processes on reserved ports.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Button("Check Reserved Ports") {
                    let threatened = viewModel.checkReservedPorts()
                    if threatened.isEmpty {
                        warningMessage = "All reserved ports are available."
                        showWarning = true
                    } else {
                        let descriptions = threatened.map { "Port \($0.port): \($0.occupant)" }.joined(separator: "\n")
                        warningMessage = "Warning: The following reserved ports are occupied:\n\(descriptions)"
                        showWarning = true
                    }
                }
            } header: {
                Text("Status")
            }
        }
        .formStyle(.grouped)
        .padding()
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
        Form {
            Section {
                Text("Custom programs let you track all PIDs for a program by its process name(s). Define which process names to track, then view and kill all processes from Settings or the main window.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("About Custom Programs")
            }

            Section {
                if appSettings.customPrograms.isEmpty {
                    Text("No custom programs configured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(appSettings.customPrograms) { program in
                        HStack(spacing: 12) {
                            Image(systemName: program.icon)
                                .font(.system(size: 16))
                                .foregroundColor(program.color)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(program.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text(program.processNames.joined(separator: ", "))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if let count = runningCounts[program.id], count > 0 {
                                Text("\(count) running")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(Theme.Status.connected)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.Badge.connectedBackground)
                                    .cornerRadius(4)
                            }

                            Button(action: {
                                editingProgram = program
                                newProgramName = program.name
                                newProcessNames = program.processNames.joined(separator: ", ")
                                newIcon = program.icon
                                newColorHex = program.colorHex
                                isAddingNew = false
                            }) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.borderless)

                            Button(action: {
                                appSettings.customPrograms.removeAll { $0.id == program.id }
                            }) {
                                Image(systemName: Theme.Icon.clearSearch)
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.Status.error)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            } header: {
                Text("Custom Programs")
            }
        }
        .formStyle(.grouped)
        .padding()
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
            ?? "Copyright © 2024–2026 Srinivas Pendela. All rights reserved."
    }

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

            Text("Version \(shortVersion)")
                .foregroundColor(.secondary)

            Text("Designed and built by Srinivas Pendela")
                .font(.caption)
                .foregroundColor(.secondary)

            if buildVersion != shortVersion {
                Text("Build \(buildVersion)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(copyrightText)
                .font(.caption2)
                .foregroundColor(.secondary)
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
