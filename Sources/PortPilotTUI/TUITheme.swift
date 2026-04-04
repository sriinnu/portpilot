// TUITheme.swift — Theme system for PortPilot TUI
//
// Provides multiple visual themes (Modern, Retro, Noir, Ocean) with
// custom colors, borders, and visual styles.

import Foundation
import TerminalTUI

// MARK: - TUI Theme Enum

enum TUITheme: String, CaseIterable {
    case modern = "Modern"
    case retro = "Retro"
    case noir = "Noir"
    case ocean = "Ocean"
    case sunset = "Sunset"

    var displayName: String { rawValue }

    var subtitle: String {
        switch self {
        case .modern: return "Dynamic Island style"
        case .retro: return "Vintage terminal"
        case .noir: return "High contrast mono"
        case .ocean: return "Deep blue tones"
        case .sunset: return "Warm amber glow"
        }
    }
}

// MARK: - Theme Colors

struct ThemeColors {
    let primary: ANSI.Color
    let secondary: ANSI.Color
    let accent: ANSI.Color
    let success: ANSI.Color
    let warning: ANSI.Color
    let error: ANSI.Color
    let text: ANSI.Color
    let textMuted: ANSI.Color
    let background: ANSI.Color
    let border: ANSI.Color
    let highlight: ANSI.Color

    static func forTheme(_ theme: TUITheme) -> ThemeColors {
        switch theme {
        case .modern:
            return ThemeColors(
                primary: .blue,
                secondary: .cyan,
                accent: .brightCyan,
                success: .green,
                warning: .yellow,
                error: .red,
                text: .brightWhite,
                textMuted: .white,
                background: .black,
                border: .blue,
                highlight: .brightBlue
            )
        case .retro:
            return ThemeColors(
                primary: .green,
                secondary: .yellow,
                accent: .brightGreen,
                success: .green,
                warning: .yellow,
                error: .red,
                text: .green,
                textMuted: .green,
                background: .black,
                border: .green,
                highlight: .brightYellow
            )
        case .noir:
            return ThemeColors(
                primary: .white,
                secondary: .brightBlack,
                accent: .brightWhite,
                success: .white,
                warning: .brightBlack,
                error: .brightWhite,
                text: .white,
                textMuted: .brightBlack,
                background: .black,
                border: .white,
                highlight: .brightWhite
            )
        case .ocean:
            return ThemeColors(
                primary: .cyan,
                secondary: .blue,
                accent: .brightCyan,
                success: .cyan,
                warning: .yellow,
                error: .red,
                text: .cyan,
                textMuted: .blue,
                background: .black,
                border: .cyan,
                highlight: .brightBlue
            )
        case .sunset:
            return ThemeColors(
                primary: .yellow,
                secondary: .red,
                accent: .brightYellow,
                success: .yellow,
                warning: .brightYellow,
                error: .brightRed,
                text: .yellow,
                textMuted: .red,
                background: .black,
                border: .yellow,
                highlight: .brightRed
            )
        }
    }
}

// MARK: - Theme Borders

struct ThemeBorders {
    let horizontal: Character
    let vertical: Character
    let topLeft: Character
    let topRight: Character
    let bottomLeft: Character
    let bottomRight: Character
    let horizontalHeavy: Character
    let verticalHeavy: Character
    let topLeftHeavy: Character
    let topRightHeavy: Character
    let bottomLeftHeavy: Character
    let bottomRightHeavy: Character

    static func forTheme(_ theme: TUITheme) -> ThemeBorders {
        switch theme {
        case .modern:
            // Rounded, modern borders
            return ThemeBorders(
                horizontal: "─",
                vertical: "│",
                topLeft: "╭",
                topRight: "╮",
                bottomLeft: "╰",
                bottomRight: "╯",
                horizontalHeavy: "━",
                verticalHeavy: "┃",
                topLeftHeavy: "┏",
                topRightHeavy: "┓",
                bottomLeftHeavy: "┗",
                bottomRightHeavy: "┛"
            )
        case .retro:
            // Classic ASCII borders
            return ThemeBorders(
                horizontal: "-",
                vertical: "|",
                topLeft: "+",
                topRight: "+",
                bottomLeft: "+",
                bottomRight: "+",
                horizontalHeavy: "=",
                verticalHeavy: "H",
                topLeftHeavy: "#",
                topRightHeavy: "#",
                bottomLeftHeavy: "#",
                bottomRightHeavy: "#"
            )
        case .noir:
            // Minimal borders
            return ThemeBorders(
                horizontal: "─",
                vertical: "│",
                topLeft: "┌",
                topRight: "┐",
                bottomLeft: "└",
                bottomRight: "┘",
                horizontalHeavy: "━",
                verticalHeavy: "║",
                topLeftHeavy: "╔",
                topRightHeavy: "╗",
                bottomLeftHeavy: "╚",
                bottomRightHeavy: "╝"
            )
        case .ocean:
            // Wavy/curved borders
            return ThemeBorders(
                horizontal: "═",
                vertical: "║",
                topLeft: "╔",
                topRight: "╗",
                bottomLeft: "╚",
                bottomRight: "╝",
                horizontalHeavy: "═",
                verticalHeavy: "║",
                topLeftHeavy: "╔",
                topRightHeavy: "╗",
                bottomLeftHeavy: "╚",
                bottomRightHeavy: "╝"
            )
        case .sunset:
            // Double-line borders
            return ThemeBorders(
                horizontal: "═",
                vertical: "║",
                topLeft: "╔",
                topRight: "╗",
                bottomLeft: "╚",
                bottomRight: "╝",
                horizontalHeavy: "█",
                verticalHeavy: "█",
                topLeftHeavy: "█",
                topRightHeavy: "█",
                bottomLeftHeavy: "█",
                bottomRightHeavy: "█"
            )
        }
    }
}

// MARK: - Theme Fonts

struct ThemeFonts {
    let titleStyle: String
    let headerStyle: String
    let bodyStyle: String
    let mutedStyle: String
    let accentStyle: String

    static func forTheme(_ theme: TUITheme, colors: ThemeColors) -> ThemeFonts {
        let baseStyle = ANSI.fg(colors.text)
        let accentStyle = ANSI.fg(colors.accent)

        switch theme {
        case .modern:
            return ThemeFonts(
                titleStyle: ANSI.bold + ANSI.fg(colors.accent),
                headerStyle: ANSI.bold + ANSI.fg(colors.primary),
                bodyStyle: baseStyle,
                mutedStyle: ANSI.dim + ANSI.fg(colors.textMuted),
                accentStyle: accentStyle
            )
        case .retro:
            return ThemeFonts(
                titleStyle: ANSI.bold + ANSI.fg(colors.accent),
                headerStyle: ANSI.bold + ANSI.underline + ANSI.fg(colors.primary),
                bodyStyle: baseStyle,
                mutedStyle: ANSI.dim + ANSI.fg(colors.textMuted),
                accentStyle: ANSI.bold + accentStyle
            )
        case .noir:
            return ThemeFonts(
                titleStyle: ANSI.bold + ANSI.inverse + ANSI.fg(colors.text),
                headerStyle: ANSI.bold + ANSI.fg(colors.text),
                bodyStyle: baseStyle,
                mutedStyle: ANSI.dim + ANSI.fg(colors.textMuted),
                accentStyle: ANSI.bold + ANSI.inverse + accentStyle
            )
        case .ocean:
            return ThemeFonts(
                titleStyle: ANSI.bold + ANSI.fg(colors.accent),
                headerStyle: ANSI.bold + ANSI.fg(colors.primary),
                bodyStyle: baseStyle,
                mutedStyle: ANSI.dim + ANSI.fg(colors.textMuted),
                accentStyle: ANSI.italic + accentStyle
            )
        case .sunset:
            return ThemeFonts(
                titleStyle: ANSI.bold + ANSI.fg(colors.accent),
                headerStyle: ANSI.bold + ANSI.fg(colors.primary),
                bodyStyle: baseStyle,
                mutedStyle: ANSI.dim + ANSI.fg(colors.textMuted),
                accentStyle: ANSI.bold + ANSI.fg(colors.accent)
            )
        }
    }
}

// MARK: - Current Theme Manager

class TUIThemeManager {
    static let shared = TUIThemeManager()

    var currentTheme: TUITheme = .modern {
        didSet {
            colors = ThemeColors.forTheme(currentTheme)
            borders = ThemeBorders.forTheme(currentTheme)
            fonts = ThemeFonts.forTheme(currentTheme, colors: colors)
        }
    }

    private(set) var colors: ThemeColors
    private(set) var borders: ThemeBorders
    private(set) var fonts: ThemeFonts

    private init() {
        self.colors = ThemeColors.forTheme(.modern)
        self.borders = ThemeBorders.forTheme(.modern)
        self.fonts = ThemeFonts.forTheme(.modern, colors: colors)
    }

    func cycleTheme() {
        let allThemes = TUITheme.allCases
        if let idx = allThemes.firstIndex(of: currentTheme) {
            currentTheme = allThemes[(idx + 1) % allThemes.count]
        }
    }
}
