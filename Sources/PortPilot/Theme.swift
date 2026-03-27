import SwiftUI
import AppKit

// MARK: - Adaptive Color Extension

extension Color {
    /// I create an adaptive SwiftUI color that respects the active macOS appearance.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? dark : light
        }))
    }
}

// MARK: - Theme Internals

private struct ThemeColorPair {
    let light: NSColor
    let dark: NSColor

    /// I bridge the NSColor pair into a dynamic SwiftUI color.
    var color: Color {
        Color(light: light, dark: dark)
    }

    /// I resolve the concrete NSColor for the current effective appearance.
    func resolved(for appearance: NSAppearance) -> NSColor {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? dark : light
    }
}

private extension NSColor {
    /// I keep surface tinting readable by falling back to the base color when blending fails.
    func blendedSafely(with color: NSColor, fraction: CGFloat) -> NSColor {
        blended(withFraction: fraction, of: color) ?? self
    }
}

private struct ThemePalette {
    let cloudflare: ThemeColorPair
    let kubernetes: ThemeColorPair
    let local: ThemeColorPair
    let database: ThemeColorPair
    let ssh: ThemeColorPair
    let orbstack: ThemeColorPair
    let proxy: ThemeColorPair
    let connected: ThemeColorPair
    let connectedBackground: ThemeColorPair
    let error: ThemeColorPair
    let warning: ThemeColorPair
    let accent: ThemeColorPair
    let sponsors: ThemeColorPair
    let treeView: ThemeColorPair
    let system: ThemeColorPair
    let userApp: ThemeColorPair
    let developerTool: ThemeColorPair
    let other: ThemeColorPair

    /// I expose the currently selected palette from persisted app settings.
    static var current: ThemePalette {
        switch AppSettings.shared.visualTheme {
        case .classic:
            return .classic
        case .graphite:
            return .graphite
        case .sunset:
            return .sunset
        case .oceanic:
            return .oceanic
        case .noir:
            return .noir
        }
    }

    private static let classic = ThemePalette(
        cloudflare: ThemeColorPair(
            light: NSColor(red: 0.90, green: 0.50, blue: 0.10, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.65, blue: 0.30, alpha: 1)
        ),
        kubernetes: ThemeColorPair(
            light: NSColor(red: 0.15, green: 0.60, blue: 0.65, alpha: 1),
            dark: NSColor(red: 0.30, green: 0.78, blue: 0.82, alpha: 1)
        ),
        local: ThemeColorPair(
            light: NSColor(red: 0.20, green: 0.68, blue: 0.30, alpha: 1),
            dark: NSColor(red: 0.35, green: 0.82, blue: 0.45, alpha: 1)
        ),
        database: ThemeColorPair(
            light: NSColor(red: 0.85, green: 0.45, blue: 0.20, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.60, blue: 0.40, alpha: 1)
        ),
        ssh: ThemeColorPair(
            light: NSColor(red: 0.55, green: 0.30, blue: 0.75, alpha: 1),
            dark: NSColor(red: 0.72, green: 0.50, blue: 0.90, alpha: 1)
        ),
        orbstack: ThemeColorPair(
            light: NSColor(red: 0.18, green: 0.48, blue: 0.88, alpha: 1),
            dark: NSColor(red: 0.38, green: 0.66, blue: 1.00, alpha: 1)
        ),
        proxy: ThemeColorPair(
            light: NSColor(red: 0.55, green: 0.30, blue: 0.75, alpha: 1),
            dark: NSColor(red: 0.72, green: 0.50, blue: 0.90, alpha: 1)
        ),
        connected: ThemeColorPair(
            light: NSColor(red: 0.20, green: 0.70, blue: 0.30, alpha: 1),
            dark: NSColor(red: 0.35, green: 0.85, blue: 0.45, alpha: 1)
        ),
        connectedBackground: ThemeColorPair(
            light: NSColor(red: 0.20, green: 0.70, blue: 0.30, alpha: 0.15),
            dark: NSColor(red: 0.35, green: 0.85, blue: 0.45, alpha: 0.20)
        ),
        error: ThemeColorPair(
            light: NSColor(red: 0.85, green: 0.20, blue: 0.20, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.40, blue: 0.40, alpha: 1)
        ),
        warning: ThemeColorPair(
            light: NSColor(red: 0.90, green: 0.55, blue: 0.10, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.70, blue: 0.30, alpha: 1)
        ),
        accent: ThemeColorPair(
            light: NSColor(red: 0.20, green: 0.45, blue: 0.90, alpha: 1),
            dark: NSColor(red: 0.35, green: 0.55, blue: 1.00, alpha: 1)
        ),
        sponsors: ThemeColorPair(
            light: NSColor(red: 0.85, green: 0.30, blue: 0.55, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.50, blue: 0.70, alpha: 1)
        ),
        treeView: ThemeColorPair(
            light: NSColor(red: 0.20, green: 0.45, blue: 0.85, alpha: 1),
            dark: NSColor(red: 0.40, green: 0.65, blue: 1.00, alpha: 1)
        ),
        system: ThemeColorPair(
            light: NSColor(red: 0.50, green: 0.50, blue: 0.55, alpha: 1),
            dark: NSColor(red: 0.65, green: 0.65, blue: 0.70, alpha: 1)
        ),
        userApp: ThemeColorPair(
            light: NSColor(red: 0.20, green: 0.45, blue: 0.85, alpha: 1),
            dark: NSColor(red: 0.40, green: 0.65, blue: 1.00, alpha: 1)
        ),
        developerTool: ThemeColorPair(
            light: NSColor(red: 0.85, green: 0.55, blue: 0.10, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.72, blue: 0.30, alpha: 1)
        ),
        other: ThemeColorPair(
            light: NSColor(red: 0.50, green: 0.50, blue: 0.55, alpha: 0.6),
            dark: NSColor(red: 0.65, green: 0.65, blue: 0.70, alpha: 0.6)
        )
    )

    private static let graphite = ThemePalette(
        cloudflare: ThemeColorPair(
            light: NSColor(red: 0.48, green: 0.54, blue: 0.68, alpha: 1),
            dark: NSColor(red: 0.64, green: 0.71, blue: 0.86, alpha: 1)
        ),
        kubernetes: ThemeColorPair(
            light: NSColor(red: 0.18, green: 0.58, blue: 0.62, alpha: 1),
            dark: NSColor(red: 0.34, green: 0.76, blue: 0.80, alpha: 1)
        ),
        local: ThemeColorPair(
            light: NSColor(red: 0.24, green: 0.64, blue: 0.48, alpha: 1),
            dark: NSColor(red: 0.42, green: 0.80, blue: 0.62, alpha: 1)
        ),
        database: ThemeColorPair(
            light: NSColor(red: 0.66, green: 0.43, blue: 0.26, alpha: 1),
            dark: NSColor(red: 0.84, green: 0.60, blue: 0.40, alpha: 1)
        ),
        ssh: ThemeColorPair(
            light: NSColor(red: 0.36, green: 0.42, blue: 0.70, alpha: 1),
            dark: NSColor(red: 0.54, green: 0.60, blue: 0.88, alpha: 1)
        ),
        orbstack: ThemeColorPair(
            light: NSColor(red: 0.24, green: 0.52, blue: 0.78, alpha: 1),
            dark: NSColor(red: 0.40, green: 0.68, blue: 0.94, alpha: 1)
        ),
        proxy: ThemeColorPair(
            light: NSColor(red: 0.36, green: 0.42, blue: 0.70, alpha: 1),
            dark: NSColor(red: 0.54, green: 0.60, blue: 0.88, alpha: 1)
        ),
        connected: ThemeColorPair(
            light: NSColor(red: 0.20, green: 0.68, blue: 0.50, alpha: 1),
            dark: NSColor(red: 0.38, green: 0.84, blue: 0.64, alpha: 1)
        ),
        connectedBackground: ThemeColorPair(
            light: NSColor(red: 0.20, green: 0.68, blue: 0.50, alpha: 0.14),
            dark: NSColor(red: 0.38, green: 0.84, blue: 0.64, alpha: 0.20)
        ),
        error: ThemeColorPair(
            light: NSColor(red: 0.76, green: 0.28, blue: 0.30, alpha: 1),
            dark: NSColor(red: 0.92, green: 0.42, blue: 0.46, alpha: 1)
        ),
        warning: ThemeColorPair(
            light: NSColor(red: 0.80, green: 0.58, blue: 0.20, alpha: 1),
            dark: NSColor(red: 0.96, green: 0.74, blue: 0.34, alpha: 1)
        ),
        accent: ThemeColorPair(
            light: NSColor(red: 0.26, green: 0.45, blue: 0.72, alpha: 1),
            dark: NSColor(red: 0.44, green: 0.63, blue: 0.92, alpha: 1)
        ),
        sponsors: ThemeColorPair(
            light: NSColor(red: 0.74, green: 0.32, blue: 0.54, alpha: 1),
            dark: NSColor(red: 0.90, green: 0.48, blue: 0.68, alpha: 1)
        ),
        treeView: ThemeColorPair(
            light: NSColor(red: 0.22, green: 0.52, blue: 0.74, alpha: 1),
            dark: NSColor(red: 0.40, green: 0.72, blue: 0.94, alpha: 1)
        ),
        system: ThemeColorPair(
            light: NSColor(red: 0.45, green: 0.48, blue: 0.56, alpha: 1),
            dark: NSColor(red: 0.60, green: 0.64, blue: 0.72, alpha: 1)
        ),
        userApp: ThemeColorPair(
            light: NSColor(red: 0.26, green: 0.45, blue: 0.72, alpha: 1),
            dark: NSColor(red: 0.44, green: 0.63, blue: 0.92, alpha: 1)
        ),
        developerTool: ThemeColorPair(
            light: NSColor(red: 0.80, green: 0.58, blue: 0.20, alpha: 1),
            dark: NSColor(red: 0.96, green: 0.74, blue: 0.34, alpha: 1)
        ),
        other: ThemeColorPair(
            light: NSColor(red: 0.45, green: 0.48, blue: 0.56, alpha: 0.65),
            dark: NSColor(red: 0.60, green: 0.64, blue: 0.72, alpha: 0.65)
        )
    )

    private static let sunset = ThemePalette(
        cloudflare: ThemeColorPair(
            light: NSColor(red: 0.92, green: 0.48, blue: 0.26, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.64, blue: 0.40, alpha: 1)
        ),
        kubernetes: ThemeColorPair(
            light: NSColor(red: 0.18, green: 0.62, blue: 0.66, alpha: 1),
            dark: NSColor(red: 0.34, green: 0.80, blue: 0.84, alpha: 1)
        ),
        local: ThemeColorPair(
            light: NSColor(red: 0.92, green: 0.56, blue: 0.24, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.72, blue: 0.40, alpha: 1)
        ),
        database: ThemeColorPair(
            light: NSColor(red: 0.80, green: 0.38, blue: 0.24, alpha: 1),
            dark: NSColor(red: 0.96, green: 0.54, blue: 0.38, alpha: 1)
        ),
        ssh: ThemeColorPair(
            light: NSColor(red: 0.62, green: 0.34, blue: 0.66, alpha: 1),
            dark: NSColor(red: 0.78, green: 0.52, blue: 0.84, alpha: 1)
        ),
        orbstack: ThemeColorPair(
            light: NSColor(red: 0.30, green: 0.52, blue: 0.92, alpha: 1),
            dark: NSColor(red: 0.48, green: 0.68, blue: 1.00, alpha: 1)
        ),
        proxy: ThemeColorPair(
            light: NSColor(red: 0.62, green: 0.34, blue: 0.66, alpha: 1),
            dark: NSColor(red: 0.78, green: 0.52, blue: 0.84, alpha: 1)
        ),
        connected: ThemeColorPair(
            light: NSColor(red: 0.24, green: 0.72, blue: 0.50, alpha: 1),
            dark: NSColor(red: 0.40, green: 0.88, blue: 0.64, alpha: 1)
        ),
        connectedBackground: ThemeColorPair(
            light: NSColor(red: 0.24, green: 0.72, blue: 0.50, alpha: 0.15),
            dark: NSColor(red: 0.40, green: 0.88, blue: 0.64, alpha: 0.22)
        ),
        error: ThemeColorPair(
            light: NSColor(red: 0.82, green: 0.24, blue: 0.28, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.42, blue: 0.46, alpha: 1)
        ),
        warning: ThemeColorPair(
            light: NSColor(red: 0.96, green: 0.62, blue: 0.18, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.78, blue: 0.34, alpha: 1)
        ),
        accent: ThemeColorPair(
            light: NSColor(red: 0.86, green: 0.40, blue: 0.30, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.56, blue: 0.42, alpha: 1)
        ),
        sponsors: ThemeColorPair(
            light: NSColor(red: 0.88, green: 0.34, blue: 0.56, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.50, blue: 0.70, alpha: 1)
        ),
        treeView: ThemeColorPair(
            light: NSColor(red: 0.26, green: 0.54, blue: 0.88, alpha: 1),
            dark: NSColor(red: 0.44, green: 0.70, blue: 1.00, alpha: 1)
        ),
        system: ThemeColorPair(
            light: NSColor(red: 0.50, green: 0.48, blue: 0.54, alpha: 1),
            dark: NSColor(red: 0.66, green: 0.64, blue: 0.72, alpha: 1)
        ),
        userApp: ThemeColorPair(
            light: NSColor(red: 0.86, green: 0.40, blue: 0.30, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.56, blue: 0.42, alpha: 1)
        ),
        developerTool: ThemeColorPair(
            light: NSColor(red: 0.96, green: 0.62, blue: 0.18, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.78, blue: 0.34, alpha: 1)
        ),
        other: ThemeColorPair(
            light: NSColor(red: 0.50, green: 0.48, blue: 0.54, alpha: 0.65),
            dark: NSColor(red: 0.66, green: 0.64, blue: 0.72, alpha: 0.65)
        )
    )

    // MARK: - Oceanic — deep blues and teals, calming and focused
    private static let oceanic = ThemePalette(
        cloudflare: ThemeColorPair(
            light: NSColor(red: 0.20, green: 0.55, blue: 0.72, alpha: 1),
            dark: NSColor(red: 0.35, green: 0.70, blue: 0.88, alpha: 1)
        ),
        kubernetes: ThemeColorPair(
            light: NSColor(red: 0.10, green: 0.58, blue: 0.60, alpha: 1),
            dark: NSColor(red: 0.22, green: 0.76, blue: 0.78, alpha: 1)
        ),
        local: ThemeColorPair(
            light: NSColor(red: 0.12, green: 0.62, blue: 0.52, alpha: 1),
            dark: NSColor(red: 0.28, green: 0.80, blue: 0.68, alpha: 1)
        ),
        database: ThemeColorPair(
            light: NSColor(red: 0.18, green: 0.44, blue: 0.68, alpha: 1),
            dark: NSColor(red: 0.34, green: 0.60, blue: 0.86, alpha: 1)
        ),
        ssh: ThemeColorPair(
            light: NSColor(red: 0.36, green: 0.32, blue: 0.68, alpha: 1),
            dark: NSColor(red: 0.52, green: 0.48, blue: 0.86, alpha: 1)
        ),
        orbstack: ThemeColorPair(
            light: NSColor(red: 0.14, green: 0.50, blue: 0.82, alpha: 1),
            dark: NSColor(red: 0.30, green: 0.66, blue: 0.98, alpha: 1)
        ),
        proxy: ThemeColorPair(
            light: NSColor(red: 0.36, green: 0.32, blue: 0.68, alpha: 1),
            dark: NSColor(red: 0.52, green: 0.48, blue: 0.86, alpha: 1)
        ),
        connected: ThemeColorPair(
            light: NSColor(red: 0.10, green: 0.64, blue: 0.56, alpha: 1),
            dark: NSColor(red: 0.26, green: 0.82, blue: 0.72, alpha: 1)
        ),
        connectedBackground: ThemeColorPair(
            light: NSColor(red: 0.10, green: 0.64, blue: 0.56, alpha: 0.14),
            dark: NSColor(red: 0.26, green: 0.82, blue: 0.72, alpha: 0.20)
        ),
        error: ThemeColorPair(
            light: NSColor(red: 0.78, green: 0.26, blue: 0.32, alpha: 1),
            dark: NSColor(red: 0.94, green: 0.44, blue: 0.48, alpha: 1)
        ),
        warning: ThemeColorPair(
            light: NSColor(red: 0.82, green: 0.62, blue: 0.18, alpha: 1),
            dark: NSColor(red: 0.98, green: 0.78, blue: 0.34, alpha: 1)
        ),
        accent: ThemeColorPair(
            light: NSColor(red: 0.12, green: 0.46, blue: 0.72, alpha: 1),
            dark: NSColor(red: 0.28, green: 0.62, blue: 0.90, alpha: 1)
        ),
        sponsors: ThemeColorPair(
            light: NSColor(red: 0.68, green: 0.30, blue: 0.58, alpha: 1),
            dark: NSColor(red: 0.86, green: 0.48, blue: 0.74, alpha: 1)
        ),
        treeView: ThemeColorPair(
            light: NSColor(red: 0.12, green: 0.50, blue: 0.76, alpha: 1),
            dark: NSColor(red: 0.30, green: 0.68, blue: 0.94, alpha: 1)
        ),
        system: ThemeColorPair(
            light: NSColor(red: 0.38, green: 0.46, blue: 0.56, alpha: 1),
            dark: NSColor(red: 0.54, green: 0.62, blue: 0.72, alpha: 1)
        ),
        userApp: ThemeColorPair(
            light: NSColor(red: 0.12, green: 0.46, blue: 0.72, alpha: 1),
            dark: NSColor(red: 0.28, green: 0.62, blue: 0.90, alpha: 1)
        ),
        developerTool: ThemeColorPair(
            light: NSColor(red: 0.10, green: 0.58, blue: 0.60, alpha: 1),
            dark: NSColor(red: 0.26, green: 0.76, blue: 0.78, alpha: 1)
        ),
        other: ThemeColorPair(
            light: NSColor(red: 0.38, green: 0.46, blue: 0.56, alpha: 0.60),
            dark: NSColor(red: 0.54, green: 0.62, blue: 0.72, alpha: 0.60)
        )
    )

    // MARK: - Noir — high-contrast monochrome with sharp accents
    private static let noir = ThemePalette(
        cloudflare: ThemeColorPair(
            light: NSColor(red: 0.40, green: 0.40, blue: 0.40, alpha: 1),
            dark: NSColor(red: 0.82, green: 0.82, blue: 0.82, alpha: 1)
        ),
        kubernetes: ThemeColorPair(
            light: NSColor(red: 0.22, green: 0.22, blue: 0.22, alpha: 1),
            dark: NSColor(red: 0.72, green: 0.72, blue: 0.72, alpha: 1)
        ),
        local: ThemeColorPair(
            light: NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1),
            dark: NSColor(red: 0.90, green: 0.90, blue: 0.90, alpha: 1)
        ),
        database: ThemeColorPair(
            light: NSColor(red: 0.30, green: 0.30, blue: 0.30, alpha: 1),
            dark: NSColor(red: 0.78, green: 0.78, blue: 0.78, alpha: 1)
        ),
        ssh: ThemeColorPair(
            light: NSColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1),
            dark: NSColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1)
        ),
        orbstack: ThemeColorPair(
            light: NSColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1),
            dark: NSColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1)
        ),
        proxy: ThemeColorPair(
            light: NSColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1),
            dark: NSColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1)
        ),
        connected: ThemeColorPair(
            light: NSColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1),
            dark: NSColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1)
        ),
        connectedBackground: ThemeColorPair(
            light: NSColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 0.10),
            dark: NSColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 0.12)
        ),
        error: ThemeColorPair(
            light: NSColor(red: 0.80, green: 0.15, blue: 0.15, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.35, blue: 0.35, alpha: 1)
        ),
        warning: ThemeColorPair(
            light: NSColor(red: 0.70, green: 0.55, blue: 0.10, alpha: 1),
            dark: NSColor(red: 0.95, green: 0.80, blue: 0.25, alpha: 1)
        ),
        accent: ThemeColorPair(
            light: NSColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1),
            dark: NSColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1)
        ),
        sponsors: ThemeColorPair(
            light: NSColor(red: 0.50, green: 0.50, blue: 0.50, alpha: 1),
            dark: NSColor(red: 0.80, green: 0.80, blue: 0.80, alpha: 1)
        ),
        treeView: ThemeColorPair(
            light: NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1),
            dark: NSColor(red: 0.90, green: 0.90, blue: 0.90, alpha: 1)
        ),
        system: ThemeColorPair(
            light: NSColor(red: 0.50, green: 0.50, blue: 0.50, alpha: 1),
            dark: NSColor(red: 0.60, green: 0.60, blue: 0.60, alpha: 1)
        ),
        userApp: ThemeColorPair(
            light: NSColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1),
            dark: NSColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1)
        ),
        developerTool: ThemeColorPair(
            light: NSColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1),
            dark: NSColor(red: 0.82, green: 0.82, blue: 0.82, alpha: 1)
        ),
        other: ThemeColorPair(
            light: NSColor(red: 0.50, green: 0.50, blue: 0.50, alpha: 0.50),
            dark: NSColor(red: 0.60, green: 0.60, blue: 0.60, alpha: 0.50)
        )
    )
}

// MARK: - Theme

enum Theme {
    private static var palette: ThemePalette {
        ThemePalette.current
    }

    /// I resolve the symbol variant from the selected icon pack.
    private static func icon(_ filled: String, _ minimal: String) -> String {
        switch AppSettings.shared.iconPack {
        case .filled:
            return filled
        case .minimal:
            return minimal
        }
    }

    // MARK: - Section Colors (per ConnectionType)

    enum Section {
        static var cloudflare: Color { Theme.palette.cloudflare.color }
        static var kubernetes: Color { Theme.palette.kubernetes.color }
        static var local: Color { Theme.palette.local.color }
        static var database: Color { Theme.palette.database.color }
        static var ssh: Color { Theme.palette.ssh.color }
        static var orbstack: Color { Theme.palette.orbstack.color }
        static var proxy: Color { Theme.palette.proxy.color }
    }

    // MARK: - Status Colors

    enum Status {
        static var connected: Color { Theme.palette.connected.color }
        static var error: Color { Theme.palette.error.color }
        static var warning: Color { Theme.palette.warning.color }
    }

    // MARK: - Action Colors

    enum Action {
        static var refresh: Color { Theme.palette.connected.color }
        static var kill: Color { Theme.palette.error.color }
        static var sponsors: Color { Theme.palette.sponsors.color }
        static var add: Color { Theme.palette.connected.color }
        static var importAction: Color { Theme.palette.accent.color }
        static var treeView: Color { Theme.palette.treeView.color }
    }

    // MARK: - Badge Colors

    enum Badge {
        static var accentBackground: Color { Theme.palette.accent.color }
        static let accentText = Color.white
        static var connectedBackground: Color { Theme.palette.connectedBackground.color }
        static var connectedText: Color { Theme.palette.connected.color }
    }

    // MARK: - Log Source Colors

    enum LogSource {
        static func color(for source: String) -> Color {
            switch source.lowercased() {
            case "kubectl":
                return Theme.Action.treeView
            case "socat":
                return Theme.Status.warning
            case "kill":
                return Theme.Action.kill
            case "proxy":
                return Theme.Section.proxy
            default:
                return Theme.Classification.other
            }
        }

        static func backgroundColor(for source: String) -> Color {
            color(for: source).opacity(0.14)
        }
    }

    // MARK: - Classification Colors

    enum Classification {
        static var system: Color { Theme.palette.system.color }
        static var userApp: Color { Theme.palette.userApp.color }
        static var developerTool: Color { Theme.palette.developerTool.color }
        static var other: Color { Theme.palette.other.color }
    }

    // MARK: - Surface Colors

    enum Surface {
        private static let windowBase = ThemeColorPair(
            light: NSColor(calibratedRed: 0.975, green: 0.978, blue: 0.985, alpha: 1),
            dark: NSColor(calibratedRed: 0.112, green: 0.118, blue: 0.132, alpha: 1)
        )

        private static let controlBase = ThemeColorPair(
            light: NSColor(calibratedRed: 0.945, green: 0.950, blue: 0.960, alpha: 1),
            dark: NSColor(calibratedRed: 0.148, green: 0.156, blue: 0.178, alpha: 1)
        )

        private static let chromeBase = ThemeColorPair(
            light: NSColor(calibratedRed: 0.905, green: 0.915, blue: 0.932, alpha: 1),
            dark: NSColor(calibratedRed: 0.182, green: 0.192, blue: 0.220, alpha: 1)
        )

        private static func blend(
            _ base: ThemeColorPair,
            with tint: ThemeColorPair,
            lightFraction: CGFloat,
            darkFraction: CGFloat
        ) -> ThemeColorPair {
            ThemeColorPair(
                light: base.light.blendedSafely(with: tint.light, fraction: lightFraction),
                dark: base.dark.blendedSafely(with: tint.dark, fraction: darkFraction)
            )
        }

        private static func isDark(_ appearance: NSAppearance) -> Bool {
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }

        private static var themedWindow: ThemeColorPair {
            blend(windowBase, with: Theme.palette.accent, lightFraction: 0.05, darkFraction: 0.18)
        }

        private static var themedControl: ThemeColorPair {
            blend(controlBase, with: Theme.palette.accent, lightFraction: 0.07, darkFraction: 0.20)
        }

        private static var themedChrome: ThemeColorPair {
            blend(chromeBase, with: Theme.palette.accent, lightFraction: 0.08, darkFraction: 0.16)
        }

        private static var themedHeader: ThemeColorPair {
            blend(chromeBase, with: Theme.palette.accent, lightFraction: 0.06, darkFraction: 0.12)
        }

        private static var themedGroupedFill: ThemeColorPair {
            blend(controlBase, with: Theme.palette.accent, lightFraction: 0.02, darkFraction: 0.06)
        }

        private static var themedRowHover: ThemeColorPair {
            ThemeColorPair(
                light: controlBase.light.blendedSafely(with: NSColor.white, fraction: 0.45),
                dark: controlBase.dark.blendedSafely(with: NSColor.white, fraction: 0.06)
            )
        }

        static var controlBackground: Color { themedControl.color }
        static var windowBackground: Color { themedWindow.color }
        static var chromeTint: Color { themedChrome.color.opacity(0.95) }
        static var headerTint: Color { themedHeader.color.opacity(0.92) }
        static var hover: Color { Theme.palette.accent.color.opacity(0.08) }
        static var rowHover: Color { themedRowHover.color.opacity(0.92) }
        static var groupedFill: Color { themedGroupedFill.color.opacity(0.94) }
        static var groupedStroke: Color { Theme.palette.accent.color.opacity(0.07) }
        static var selected: Color { Theme.palette.accent.color.opacity(0.18) }

        static func panelFill(for appearance: NSAppearance) -> NSColor {
            themedControl.resolved(for: appearance).withAlphaComponent(isDark(appearance) ? 0.96 : 0.90)
        }

        static func panelBorder(for appearance: NSAppearance) -> NSColor {
            Theme.palette.accent.resolved(for: appearance).withAlphaComponent(isDark(appearance) ? 0.34 : 0.16)
        }
    }

    // MARK: - SF Symbol Constants

    enum Icon {
        // Connection types
        static var local: String { Theme.icon("desktopcomputer", "desktopcomputer") }
        static var database: String { Theme.icon("cylinder.fill", "cylinder") }
        static var kubernetes: String { Theme.icon("cube.fill", "cube") }
        static var cloudflare: String { Theme.icon("cloud.fill", "cloud") }
        static var ssh: String { Theme.icon("terminal.fill", "terminal") }
        static var orbstack: String { Theme.icon("shippingbox.fill", "shippingbox") }
        static var tunnels: String { Theme.icon("point.3.connected.trianglepath.dotted", "point.3.connected.trianglepath.dotted") }

        // Navigation / tabs
        static var appLogo: String { Theme.icon("network.badge.shield.half.filled", "network") }
        static var portsTab: String { Theme.icon("network", "network") }
        static var socketsTab: String { Theme.icon("point.3.connected.trianglepath.dotted", "point.3.connected.trianglepath.dotted") }

        // Actions
        static var refresh: String { Theme.icon("arrow.clockwise.circle.fill", "arrow.clockwise") }
        static var kill: String { Theme.icon("stop.circle.fill", "stop.circle") }
        static var killAll: String { Theme.icon("xmark.circle.fill", "xmark.circle") }
        static var add: String { Theme.icon("plus.circle.fill", "plus.circle") }
        static var importFile: String { Theme.icon("square.and.arrow.down.fill", "square.and.arrow.down") }
        static var copy: String { Theme.icon("doc.on.doc.fill", "doc.on.doc") }
        static var trash: String { Theme.icon("trash.fill", "trash") }
        static var settings: String { Theme.icon("gearshape.fill", "gearshape") }
        static var quit: String { Theme.icon("power.circle.fill", "power.circle") }
        static var openWindow: String { Theme.icon("macwindow.on.rectangle", "macwindow") }
        static var sponsors: String { Theme.icon("heart.fill", "heart") }
        static var treeView: String { Theme.icon("list.bullet.indent", "list.bullet.indent") }
        static var appearance: String { Theme.icon("paintpalette.fill", "paintpalette") }
        static var systemMode: String { Theme.icon("circle.lefthalf.filled", "circle.lefthalf.filled") }
        static var lightMode: String { Theme.icon("sun.max.fill", "sun.max") }
        static var darkMode: String { Theme.icon("moon.stars.fill", "moon.stars") }

        // Status
        static var connected: String { Theme.icon("antenna.radiowaves.left.and.right.circle.fill", "antenna.radiowaves.left.and.right") }
        static var globe: String { Theme.icon("globe.americas.fill", "globe.americas") }
        static var notification: String { Theme.icon("bell.fill", "bell") }
        static var notificationOff: String { Theme.icon("bell.slash.fill", "bell.slash") }
        static var checkmark: String { Theme.icon("checkmark.circle.fill", "checkmark.circle") }

        // Config field icons
        static var name: String { Theme.icon("link.circle.fill", "link.circle") }
        static var type: String { Theme.icon("display", "display") }
        static var process: String { Theme.icon("terminal.fill", "terminal") }
        static var pid: String { Theme.icon("number.circle.fill", "number.circle") }
        static var user: String { Theme.icon("person.fill", "person") }
        static var ppid: String { Theme.icon("person.2.fill", "person.2") }
        static var uptime: String { Theme.icon("clock.fill", "clock") }
        static var workingDirectory: String { Theme.icon("folder.fill", "folder") }

        // Options icons
        static var autoReconnect: String { refresh }
        static var enabled: String { checkmark }
        static var notifyConnect: String { notification }
        static var notifyDisconnect: String { notificationOff }

        // Proxy
        static var proxy: String { Theme.icon("arrow.left.arrow.right.circle", "arrow.left.arrow.right.circle") }
        static var proxyActive: String { Theme.icon("arrow.left.arrow.right.circle.fill", "arrow.left.arrow.right.circle") }

        // Port mapping
        static var portArrow: String { Theme.icon("arrow.left.arrow.right", "arrow.left.arrow.right") }

        // Search / nav
        static var search: String { Theme.icon("magnifyingglass.circle.fill", "magnifyingglass") }
        static var clearSearch: String { Theme.icon("xmark.circle.fill", "xmark.circle") }
        static var chevronDown: String { Theme.icon("chevron.down", "chevron.down") }
        static var chevronRight: String { Theme.icon("chevron.right", "chevron.right") }

        // Process classification
        static var hideSystem: String { Theme.icon("eye.slash.fill", "eye.slash") }
        static var showSystem: String { Theme.icon("eye.fill", "eye") }
    }

    // MARK: - Config Field Icon Colors

    enum ConfigIcon {
        static var name: Color { Theme.Action.treeView }
        static var type: Color { Theme.Action.add }
        static var process: Color { Theme.Section.kubernetes }
        static var pid: Color { Theme.Classification.system }
        static var user: Color { Theme.Section.ssh }
        static var ppid: Color { Theme.Section.orbstack }
        static var uptime: Color { Theme.Status.warning }
        static var workingDirectory: Color { Theme.Action.treeView }
    }

    // MARK: - Option Toggle Icon Colors

    enum OptionIcon {
        static var autoReconnect: Color { Theme.Section.kubernetes }
        static var enabled: Color { Theme.Action.add }
        static var notifyConnect: Color { Theme.Status.warning }
        static var notifyDisconnect: Color { Theme.Classification.system }
    }

    // MARK: - Port Mapping Colors

    enum PortMapping {
        static var localStroke: Color { Theme.Action.treeView.opacity(0.5) }
        static var localFill: Color { Theme.Action.treeView.opacity(0.08) }
        static var protocolStroke: Color { Theme.Status.warning.opacity(0.5) }
        static var protocolFill: Color { Theme.Status.warning.opacity(0.08) }
        static var remoteStroke: Color { Theme.Action.add.opacity(0.5) }
        static var remoteFill: Color { Theme.Action.add.opacity(0.08) }
    }

    // MARK: - Size Constants

    enum Size {
        static let statusDotLarge: CGFloat = 8
        static let statusDotSmall: CGFloat = 6
        static let cornerRadius: CGFloat = 6
        static let cornerRadiusSmall: CGFloat = 4
        static let sectionIconSize: CGFloat = 14
        static let actionIconSize: CGFloat = 12
        static let badgeIconSize: CGFloat = 11
    }
}
