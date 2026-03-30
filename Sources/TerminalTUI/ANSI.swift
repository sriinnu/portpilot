// ANSI.swift — ANSI escape code constants and builders
//
// Provides all the escape sequences needed for colors, styles, cursor movement,
// and screen control. Designed as a zero-dependency, value-type API.
//
// Usage:
//   let styled = ANSI.bold + ANSI.fg(.cyan) + "Hello" + ANSI.reset
//   Terminal.write(styled)

public enum ANSI {

    // MARK: - Reset

    public static let reset = "\u{001B}[0m"

    // MARK: - Text Styles

    public static let bold          = "\u{001B}[1m"
    public static let dim           = "\u{001B}[2m"
    public static let italic        = "\u{001B}[3m"
    public static let underline     = "\u{001B}[4m"
    public static let blink         = "\u{001B}[5m"
    public static let inverse       = "\u{001B}[7m"
    public static let strikethrough = "\u{001B}[9m"

    // MARK: - Cursor

    public static let hideCursor = "\u{001B}[?25l"
    public static let showCursor = "\u{001B}[?25h"

    /// Move cursor to (row, col) — both 0-indexed, converted to 1-indexed for ANSI
    public static func moveTo(row: Int, col: Int) -> String {
        "\u{001B}[\(row + 1);\(col + 1)H"
    }

    // MARK: - Screen Control

    public static let clearScreen    = "\u{001B}[2J"
    public static let clearLine      = "\u{001B}[2K"
    public static let clearToEnd     = "\u{001B}[0J"
    public static let enterAltScreen = "\u{001B}[?1049h"
    public static let exitAltScreen  = "\u{001B}[?1049l"

    /// Erase from cursor to end of line
    public static let eraseToEOL = "\u{001B}[K"

    // MARK: - 16-Color Palette

    /// Standard ANSI foreground/background colors.
    /// Use `fg(.red)` and `bg(.blue)` for readable code.
    public enum Color: Int, CaseIterable, Sendable {
        case black         = 0
        case red           = 1
        case green         = 2
        case yellow        = 3
        case blue          = 4
        case magenta       = 5
        case cyan          = 6
        case white         = 7
        // Bright variants
        case brightBlack   = 8
        case brightRed     = 9
        case brightGreen   = 10
        case brightYellow  = 11
        case brightBlue    = 12
        case brightMagenta = 13
        case brightCyan    = 14
        case brightWhite   = 15

        /// Convenience aliases
        public static let gray = Color.brightBlack
    }

    /// Set foreground color (16-color)
    public static func fg(_ color: Color) -> String {
        let code = color.rawValue < 8 ? 30 + color.rawValue : 82 + color.rawValue
        return "\u{001B}[\(code)m"
    }

    /// Set background color (16-color)
    public static func bg(_ color: Color) -> String {
        let code = color.rawValue < 8 ? 40 + color.rawValue : 92 + color.rawValue
        return "\u{001B}[\(code)m"
    }

    // MARK: - 256-Color / TrueColor

    /// Set foreground using xterm 256-color palette (0–255)
    public static func fg256(_ code: Int) -> String {
        "\u{001B}[38;5;\(code)m"
    }

    /// Set background using xterm 256-color palette (0–255)
    public static func bg256(_ code: Int) -> String {
        "\u{001B}[48;5;\(code)m"
    }

    /// Set foreground using 24-bit RGB
    public static func fgRGB(_ r: Int, _ g: Int, _ b: Int) -> String {
        "\u{001B}[38;2;\(r);\(g);\(b)m"
    }

    /// Set background using 24-bit RGB
    public static func bgRGB(_ r: Int, _ g: Int, _ b: Int) -> String {
        "\u{001B}[48;2;\(r);\(g);\(b)m"
    }

    // MARK: - Composable Style Builder

    /// Combine multiple style codes into one string.
    ///
    /// Usage:
    ///   let header = ANSI.style(.bold, fg: .cyan) + "Title" + ANSI.reset
    public static func style(_ styles: String..., fg fgColor: Color? = nil, bg bgColor: Color? = nil) -> String {
        var parts = styles
        if let fgColor { parts.append(fg(fgColor)) }
        if let bgColor { parts.append(bg(bgColor)) }
        return parts.joined()
    }
}
