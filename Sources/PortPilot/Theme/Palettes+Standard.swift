import SwiftUI
import AppKit

extension ThemePalette {
    static let classic = ThemePalette(
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

    static let graphite = ThemePalette(
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

    static let sunset = ThemePalette(
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
    static let oceanic = ThemePalette(
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
    static let noir = ThemePalette(
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
