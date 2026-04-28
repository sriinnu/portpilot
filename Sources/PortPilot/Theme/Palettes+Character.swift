import SwiftUI
import AppKit

extension ThemePalette {
    static let retro = ThemePalette(
        cloudflare: ThemeColorPair(
            light: NSColor(red: 0.72, green: 0.45, blue: 0.20, alpha: 1),   // warm brown
            dark: NSColor(red: 0.88, green: 0.62, blue: 0.35, alpha: 1)
        ),
        kubernetes: ThemeColorPair(
            light: NSColor(red: 0.35, green: 0.52, blue: 0.42, alpha: 1),   // muted teal-green
            dark: NSColor(red: 0.45, green: 0.68, blue: 0.55, alpha: 1)
        ),
        local: ThemeColorPair(
            light: NSColor(red: 0.38, green: 0.55, blue: 0.28, alpha: 1),   // olive green
            dark: NSColor(red: 0.50, green: 0.75, blue: 0.35, alpha: 1)     // phosphor green
        ),
        database: ThemeColorPair(
            light: NSColor(red: 0.75, green: 0.50, blue: 0.25, alpha: 1),   // warm amber
            dark: NSColor(red: 0.90, green: 0.65, blue: 0.35, alpha: 1)
        ),
        ssh: ThemeColorPair(
            light: NSColor(red: 0.52, green: 0.35, blue: 0.55, alpha: 1),   // muted plum
            dark: NSColor(red: 0.68, green: 0.50, blue: 0.72, alpha: 1)
        ),
        orbstack: ThemeColorPair(
            light: NSColor(red: 0.40, green: 0.45, blue: 0.62, alpha: 1),   // dusty blue
            dark: NSColor(red: 0.55, green: 0.62, blue: 0.80, alpha: 1)
        ),
        proxy: ThemeColorPair(
            light: NSColor(red: 0.52, green: 0.35, blue: 0.55, alpha: 1),
            dark: NSColor(red: 0.68, green: 0.50, blue: 0.72, alpha: 1)
        ),
        connected: ThemeColorPair(
            light: NSColor(red: 0.35, green: 0.58, blue: 0.30, alpha: 1),   // forest green
            dark: NSColor(red: 0.40, green: 0.78, blue: 0.32, alpha: 1)     // phosphor green
        ),
        connectedBackground: ThemeColorPair(
            light: NSColor(red: 0.35, green: 0.58, blue: 0.30, alpha: 0.12),
            dark: NSColor(red: 0.40, green: 0.78, blue: 0.32, alpha: 0.18)
        ),
        error: ThemeColorPair(
            light: NSColor(red: 0.72, green: 0.22, blue: 0.18, alpha: 1),   // burnt red/burgundy
            dark: NSColor(red: 0.90, green: 0.38, blue: 0.32, alpha: 1)
        ),
        warning: ThemeColorPair(
            light: NSColor(red: 0.80, green: 0.55, blue: 0.15, alpha: 1),   // deep amber
            dark: NSColor(red: 0.95, green: 0.72, blue: 0.28, alpha: 1)
        ),
        accent: ThemeColorPair(
            light: NSColor(red: 0.65, green: 0.42, blue: 0.18, alpha: 1),   // warm brown accent
            dark: NSColor(red: 0.85, green: 0.60, blue: 0.28, alpha: 1)     // amber accent
        ),
        sponsors: ThemeColorPair(
            light: NSColor(red: 0.70, green: 0.32, blue: 0.38, alpha: 1),   // dusty rose
            dark: NSColor(red: 0.88, green: 0.48, blue: 0.52, alpha: 1)
        ),
        treeView: ThemeColorPair(
            light: NSColor(red: 0.45, green: 0.42, blue: 0.62, alpha: 1),   // muted indigo
            dark: NSColor(red: 0.60, green: 0.58, blue: 0.82, alpha: 1)
        ),
        system: ThemeColorPair(
            light: NSColor(red: 0.52, green: 0.48, blue: 0.42, alpha: 1),   // warm gray
            dark: NSColor(red: 0.65, green: 0.60, blue: 0.55, alpha: 1)
        ),
        userApp: ThemeColorPair(
            light: NSColor(red: 0.45, green: 0.42, blue: 0.62, alpha: 1),
            dark: NSColor(red: 0.60, green: 0.58, blue: 0.82, alpha: 1)
        ),
        developerTool: ThemeColorPair(
            light: NSColor(red: 0.75, green: 0.52, blue: 0.18, alpha: 1),   // golden amber
            dark: NSColor(red: 0.92, green: 0.70, blue: 0.30, alpha: 1)
        ),
        other: ThemeColorPair(
            light: NSColor(red: 0.52, green: 0.48, blue: 0.42, alpha: 0.6),
            dark: NSColor(red: 0.65, green: 0.60, blue: 0.55, alpha: 0.6)
        )
    )

    // MARK: - Terminal — phosphor green on deep charcoal, CRT-era
    static let terminal = ThemePalette(
        cloudflare: ThemeColorPair(
            light: NSColor(red: 0.75, green: 0.48, blue: 0.10, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.70, blue: 0.20, alpha: 1)
        ),
        kubernetes: ThemeColorPair(
            light: NSColor(red: 0.10, green: 0.55, blue: 0.45, alpha: 1),
            dark: NSColor(red: 0.22, green: 0.90, blue: 0.75, alpha: 1)
        ),
        local: ThemeColorPair(
            light: NSColor(red: 0.20, green: 0.62, blue: 0.28, alpha: 1),
            dark: NSColor(red: 0.20, green: 1.00, blue: 0.36, alpha: 1)
        ),
        database: ThemeColorPair(
            light: NSColor(red: 0.70, green: 0.58, blue: 0.15, alpha: 1),
            dark: NSColor(red: 0.95, green: 0.82, blue: 0.25, alpha: 1)
        ),
        ssh: ThemeColorPair(
            light: NSColor(red: 0.32, green: 0.48, blue: 0.72, alpha: 1),
            dark: NSColor(red: 0.50, green: 0.82, blue: 1.00, alpha: 1)
        ),
        orbstack: ThemeColorPair(
            light: NSColor(red: 0.18, green: 0.55, blue: 0.70, alpha: 1),
            dark: NSColor(red: 0.35, green: 0.86, blue: 1.00, alpha: 1)
        ),
        proxy: ThemeColorPair(
            light: NSColor(red: 0.55, green: 0.30, blue: 0.70, alpha: 1),
            dark: NSColor(red: 0.80, green: 0.60, blue: 1.00, alpha: 1)
        ),
        connected: ThemeColorPair(
            light: NSColor(red: 0.20, green: 0.65, blue: 0.28, alpha: 1),
            dark: NSColor(red: 0.20, green: 1.00, blue: 0.36, alpha: 1)
        ),
        connectedBackground: ThemeColorPair(
            light: NSColor(red: 0.20, green: 0.65, blue: 0.28, alpha: 0.14),
            dark: NSColor(red: 0.20, green: 1.00, blue: 0.36, alpha: 0.22)
        ),
        error: ThemeColorPair(
            light: NSColor(red: 0.82, green: 0.14, blue: 0.18, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.40, blue: 0.40, alpha: 1)
        ),
        warning: ThemeColorPair(
            light: NSColor(red: 0.88, green: 0.58, blue: 0.05, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.78, blue: 0.20, alpha: 1)
        ),
        accent: ThemeColorPair(
            light: NSColor(red: 0.18, green: 0.60, blue: 0.28, alpha: 1),
            dark: NSColor(red: 0.20, green: 1.00, blue: 0.36, alpha: 1)
        ),
        sponsors: ThemeColorPair(
            light: NSColor(red: 0.78, green: 0.28, blue: 0.48, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.50, blue: 0.70, alpha: 1)
        ),
        treeView: ThemeColorPair(
            light: NSColor(red: 0.18, green: 0.55, blue: 0.70, alpha: 1),
            dark: NSColor(red: 0.35, green: 0.86, blue: 1.00, alpha: 1)
        ),
        system: ThemeColorPair(
            light: NSColor(red: 0.42, green: 0.48, blue: 0.44, alpha: 1),
            dark: NSColor(red: 0.58, green: 0.68, blue: 0.60, alpha: 1)
        ),
        userApp: ThemeColorPair(
            light: NSColor(red: 0.18, green: 0.60, blue: 0.28, alpha: 1),
            dark: NSColor(red: 0.20, green: 1.00, blue: 0.36, alpha: 1)
        ),
        developerTool: ThemeColorPair(
            light: NSColor(red: 0.88, green: 0.58, blue: 0.05, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.78, blue: 0.20, alpha: 1)
        ),
        other: ThemeColorPair(
            light: NSColor(red: 0.42, green: 0.48, blue: 0.44, alpha: 0.6),
            dark: NSColor(red: 0.58, green: 0.68, blue: 0.60, alpha: 0.6)
        )
    )

    // MARK: - Paperwhite — editorial, minimal, electric-blue accent
    static let paperwhite = ThemePalette(
        cloudflare: ThemeColorPair(
            light: NSColor(red: 0.92, green: 0.48, blue: 0.08, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.62, blue: 0.20, alpha: 1)
        ),
        kubernetes: ThemeColorPair(
            light: NSColor(red: 0.00, green: 0.55, blue: 0.60, alpha: 1),
            dark: NSColor(red: 0.18, green: 0.78, blue: 0.84, alpha: 1)
        ),
        local: ThemeColorPair(
            light: NSColor(red: 0.18, green: 0.62, blue: 0.28, alpha: 1),
            dark: NSColor(red: 0.32, green: 0.82, blue: 0.42, alpha: 1)
        ),
        database: ThemeColorPair(
            light: NSColor(red: 0.78, green: 0.38, blue: 0.18, alpha: 1),
            dark: NSColor(red: 0.96, green: 0.56, blue: 0.32, alpha: 1)
        ),
        ssh: ThemeColorPair(
            light: NSColor(red: 0.48, green: 0.24, blue: 0.72, alpha: 1),
            dark: NSColor(red: 0.68, green: 0.48, blue: 0.92, alpha: 1)
        ),
        orbstack: ThemeColorPair(
            light: NSColor(red: 0.00, green: 0.40, blue: 1.00, alpha: 1),
            dark: NSColor(red: 0.30, green: 0.60, blue: 1.00, alpha: 1)
        ),
        proxy: ThemeColorPair(
            light: NSColor(red: 0.48, green: 0.24, blue: 0.72, alpha: 1),
            dark: NSColor(red: 0.68, green: 0.48, blue: 0.92, alpha: 1)
        ),
        connected: ThemeColorPair(
            light: NSColor(red: 0.18, green: 0.70, blue: 0.32, alpha: 1),
            dark: NSColor(red: 0.30, green: 0.85, blue: 0.45, alpha: 1)
        ),
        connectedBackground: ThemeColorPair(
            light: NSColor(red: 0.18, green: 0.70, blue: 0.32, alpha: 0.12),
            dark: NSColor(red: 0.30, green: 0.85, blue: 0.45, alpha: 0.18)
        ),
        error: ThemeColorPair(
            light: NSColor(red: 0.90, green: 0.18, blue: 0.15, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.38, blue: 0.32, alpha: 1)
        ),
        warning: ThemeColorPair(
            light: NSColor(red: 1.00, green: 0.58, blue: 0.00, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.72, blue: 0.20, alpha: 1)
        ),
        accent: ThemeColorPair(
            light: NSColor(red: 0.00, green: 0.40, blue: 1.00, alpha: 1),
            dark: NSColor(red: 0.30, green: 0.60, blue: 1.00, alpha: 1)
        ),
        sponsors: ThemeColorPair(
            light: NSColor(red: 0.90, green: 0.22, blue: 0.50, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.42, blue: 0.68, alpha: 1)
        ),
        treeView: ThemeColorPair(
            light: NSColor(red: 0.00, green: 0.40, blue: 1.00, alpha: 1),
            dark: NSColor(red: 0.30, green: 0.60, blue: 1.00, alpha: 1)
        ),
        system: ThemeColorPair(
            light: NSColor(red: 0.50, green: 0.52, blue: 0.55, alpha: 1),
            dark: NSColor(red: 0.66, green: 0.68, blue: 0.72, alpha: 1)
        ),
        userApp: ThemeColorPair(
            light: NSColor(red: 0.00, green: 0.40, blue: 1.00, alpha: 1),
            dark: NSColor(red: 0.30, green: 0.60, blue: 1.00, alpha: 1)
        ),
        developerTool: ThemeColorPair(
            light: NSColor(red: 1.00, green: 0.58, blue: 0.00, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.72, blue: 0.20, alpha: 1)
        ),
        other: ThemeColorPair(
            light: NSColor(red: 0.50, green: 0.52, blue: 0.55, alpha: 0.6),
            dark: NSColor(red: 0.66, green: 0.68, blue: 0.72, alpha: 0.6)
        )
    )

    // MARK: - Synthwave — magenta + cyan on deep indigo, late 1984
    static let synthwave = ThemePalette(
        cloudflare: ThemeColorPair(
            light: NSColor(red: 0.90, green: 0.38, blue: 0.15, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.55, blue: 0.25, alpha: 1)
        ),
        kubernetes: ThemeColorPair(
            light: NSColor(red: 0.00, green: 0.72, blue: 0.85, alpha: 1),
            dark: NSColor(red: 0.00, green: 0.94, blue: 1.00, alpha: 1)
        ),
        local: ThemeColorPair(
            light: NSColor(red: 0.92, green: 0.15, blue: 0.60, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.30, blue: 0.78, alpha: 1)
        ),
        database: ThemeColorPair(
            light: NSColor(red: 0.75, green: 0.00, blue: 0.55, alpha: 1),
            dark: NSColor(red: 0.95, green: 0.30, blue: 0.80, alpha: 1)
        ),
        ssh: ThemeColorPair(
            light: NSColor(red: 0.55, green: 0.25, blue: 0.92, alpha: 1),
            dark: NSColor(red: 0.72, green: 0.48, blue: 1.00, alpha: 1)
        ),
        orbstack: ThemeColorPair(
            light: NSColor(red: 0.00, green: 0.72, blue: 0.85, alpha: 1),
            dark: NSColor(red: 0.00, green: 0.94, blue: 1.00, alpha: 1)
        ),
        proxy: ThemeColorPair(
            light: NSColor(red: 0.55, green: 0.25, blue: 0.92, alpha: 1),
            dark: NSColor(red: 0.72, green: 0.48, blue: 1.00, alpha: 1)
        ),
        connected: ThemeColorPair(
            light: NSColor(red: 0.00, green: 0.72, blue: 0.85, alpha: 1),
            dark: NSColor(red: 0.00, green: 0.94, blue: 1.00, alpha: 1)
        ),
        connectedBackground: ThemeColorPair(
            light: NSColor(red: 0.00, green: 0.72, blue: 0.85, alpha: 0.15),
            dark: NSColor(red: 0.00, green: 0.94, blue: 1.00, alpha: 0.24)
        ),
        error: ThemeColorPair(
            light: NSColor(red: 1.00, green: 0.25, blue: 0.35, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.42, blue: 0.54, alpha: 1)
        ),
        warning: ThemeColorPair(
            light: NSColor(red: 1.00, green: 0.62, blue: 0.12, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.78, blue: 0.28, alpha: 1)
        ),
        accent: ThemeColorPair(
            light: NSColor(red: 0.92, green: 0.15, blue: 0.60, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.30, blue: 0.78, alpha: 1)
        ),
        sponsors: ThemeColorPair(
            light: NSColor(red: 0.92, green: 0.15, blue: 0.60, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.30, blue: 0.78, alpha: 1)
        ),
        treeView: ThemeColorPair(
            light: NSColor(red: 0.00, green: 0.72, blue: 0.85, alpha: 1),
            dark: NSColor(red: 0.00, green: 0.94, blue: 1.00, alpha: 1)
        ),
        system: ThemeColorPair(
            light: NSColor(red: 0.52, green: 0.48, blue: 0.62, alpha: 1),
            dark: NSColor(red: 0.68, green: 0.64, blue: 0.80, alpha: 1)
        ),
        userApp: ThemeColorPair(
            light: NSColor(red: 0.92, green: 0.15, blue: 0.60, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.30, blue: 0.78, alpha: 1)
        ),
        developerTool: ThemeColorPair(
            light: NSColor(red: 0.55, green: 0.25, blue: 0.92, alpha: 1),
            dark: NSColor(red: 0.72, green: 0.48, blue: 1.00, alpha: 1)
        ),
        other: ThemeColorPair(
            light: NSColor(red: 0.52, green: 0.48, blue: 0.62, alpha: 0.6),
            dark: NSColor(red: 0.68, green: 0.64, blue: 0.80, alpha: 0.6)
        )
    )

    // MARK: - Solarized — developer classic, warm cream + sage + gold
    static let solarized = ThemePalette(
        cloudflare: ThemeColorPair(
            light: NSColor(red: 0.80, green: 0.29, blue: 0.09, alpha: 1),
            dark: NSColor(red: 0.92, green: 0.44, blue: 0.20, alpha: 1)
        ),
        kubernetes: ThemeColorPair(
            light: NSColor(red: 0.16, green: 0.63, blue: 0.60, alpha: 1),
            dark: NSColor(red: 0.24, green: 0.78, blue: 0.75, alpha: 1)
        ),
        local: ThemeColorPair(
            light: NSColor(red: 0.52, green: 0.60, blue: 0.00, alpha: 1),
            dark: NSColor(red: 0.68, green: 0.78, blue: 0.18, alpha: 1)
        ),
        database: ThemeColorPair(
            light: NSColor(red: 0.71, green: 0.54, blue: 0.00, alpha: 1),
            dark: NSColor(red: 0.88, green: 0.70, blue: 0.18, alpha: 1)
        ),
        ssh: ThemeColorPair(
            light: NSColor(red: 0.42, green: 0.44, blue: 0.77, alpha: 1),
            dark: NSColor(red: 0.60, green: 0.62, blue: 0.88, alpha: 1)
        ),
        orbstack: ThemeColorPair(
            light: NSColor(red: 0.15, green: 0.55, blue: 0.82, alpha: 1),
            dark: NSColor(red: 0.35, green: 0.70, blue: 0.94, alpha: 1)
        ),
        proxy: ThemeColorPair(
            light: NSColor(red: 0.83, green: 0.21, blue: 0.51, alpha: 1),
            dark: NSColor(red: 0.95, green: 0.40, blue: 0.66, alpha: 1)
        ),
        connected: ThemeColorPair(
            light: NSColor(red: 0.52, green: 0.60, blue: 0.00, alpha: 1),
            dark: NSColor(red: 0.68, green: 0.78, blue: 0.18, alpha: 1)
        ),
        connectedBackground: ThemeColorPair(
            light: NSColor(red: 0.52, green: 0.60, blue: 0.00, alpha: 0.14),
            dark: NSColor(red: 0.68, green: 0.78, blue: 0.18, alpha: 0.20)
        ),
        error: ThemeColorPair(
            light: NSColor(red: 0.86, green: 0.20, blue: 0.18, alpha: 1),
            dark: NSColor(red: 0.98, green: 0.38, blue: 0.36, alpha: 1)
        ),
        warning: ThemeColorPair(
            light: NSColor(red: 0.71, green: 0.54, blue: 0.00, alpha: 1),
            dark: NSColor(red: 0.88, green: 0.70, blue: 0.18, alpha: 1)
        ),
        accent: ThemeColorPair(
            light: NSColor(red: 0.16, green: 0.63, blue: 0.60, alpha: 1),
            dark: NSColor(red: 0.24, green: 0.78, blue: 0.75, alpha: 1)
        ),
        sponsors: ThemeColorPair(
            light: NSColor(red: 0.83, green: 0.21, blue: 0.51, alpha: 1),
            dark: NSColor(red: 0.95, green: 0.40, blue: 0.66, alpha: 1)
        ),
        treeView: ThemeColorPair(
            light: NSColor(red: 0.15, green: 0.55, blue: 0.82, alpha: 1),
            dark: NSColor(red: 0.35, green: 0.70, blue: 0.94, alpha: 1)
        ),
        system: ThemeColorPair(
            light: NSColor(red: 0.40, green: 0.48, blue: 0.51, alpha: 1),
            dark: NSColor(red: 0.58, green: 0.65, blue: 0.67, alpha: 1)
        ),
        userApp: ThemeColorPair(
            light: NSColor(red: 0.15, green: 0.55, blue: 0.82, alpha: 1),
            dark: NSColor(red: 0.35, green: 0.70, blue: 0.94, alpha: 1)
        ),
        developerTool: ThemeColorPair(
            light: NSColor(red: 0.71, green: 0.54, blue: 0.00, alpha: 1),
            dark: NSColor(red: 0.88, green: 0.70, blue: 0.18, alpha: 1)
        ),
        other: ThemeColorPair(
            light: NSColor(red: 0.40, green: 0.48, blue: 0.51, alpha: 0.6),
            dark: NSColor(red: 0.58, green: 0.65, blue: 0.67, alpha: 0.6)
        )
    )
}
