// Box.swift — Bordered box widget with optional title
//
// Draws a rectangular border around content. Supports multiple border styles
// and an optional title rendered in the top border.
//
// Usage:
//   let box = Box(title: "Ports", style: .rounded) { screen, origin, size in
//       // render content inside the box
//   }
//   box.render(into: &screen, at: .zero, size: Size(width: 60, height: 20))

// MARK: - Border Style

/// Character set for drawing box borders
public struct BorderStyle: Sendable {
    public let topLeft: Character
    public let topRight: Character
    public let bottomLeft: Character
    public let bottomRight: Character
    public let horizontal: Character
    public let vertical: Character

    public init(
        topLeft: Character, topRight: Character,
        bottomLeft: Character, bottomRight: Character,
        horizontal: Character, vertical: Character
    ) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
        self.horizontal = horizontal
        self.vertical = vertical
    }

    /// ┌──┐ └──┘
    public static let single = BorderStyle(
        topLeft: "┌", topRight: "┐", bottomLeft: "└", bottomRight: "┘",
        horizontal: "─", vertical: "│"
    )

    /// ╭──╮ ╰──╯
    public static let rounded = BorderStyle(
        topLeft: "╭", topRight: "╮", bottomLeft: "╰", bottomRight: "╯",
        horizontal: "─", vertical: "│"
    )

    /// ┏━━┓ ┗━━┛
    public static let heavy = BorderStyle(
        topLeft: "┏", topRight: "┓", bottomLeft: "┗", bottomRight: "┛",
        horizontal: "━", vertical: "┃"
    )

    /// ╔══╗ ╚══╝
    public static let double = BorderStyle(
        topLeft: "╔", topRight: "╗", bottomLeft: "╚", bottomRight: "╝",
        horizontal: "═", vertical: "║"
    )

    /// No border (invisible)
    public static let none = BorderStyle(
        topLeft: " ", topRight: " ", bottomLeft: " ", bottomRight: " ",
        horizontal: " ", vertical: " "
    )
}

// MARK: - Box Widget

/// A bordered container that renders child content inside its inset area.
public struct Box: Widget {
    public let title: String?
    public let style: BorderStyle
    public let borderStyle: String  // ANSI style for the border characters
    public let titleStyle: String   // ANSI style for the title text
    public let content: (inout Screen, Point, Size) -> Void

    /// Create a box with an optional title and border style.
    ///
    /// - Parameters:
    ///   - title: Optional title rendered in the top border
    ///   - style: Border character set (default: `.rounded`)
    ///   - borderStyle: ANSI escape style for border (default: dim)
    ///   - titleStyle: ANSI escape style for title text (default: bold cyan)
    ///   - content: Closure that renders the box's inner content
    public init(
        title: String? = nil,
        style: BorderStyle = .rounded,
        borderStyle: String = ANSI.dim,
        titleStyle: String = ANSI.bold + ANSI.fg(.cyan),
        content: @escaping (inout Screen, Point, Size) -> Void
    ) {
        self.title = title
        self.style = style
        self.borderStyle = borderStyle
        self.titleStyle = titleStyle
        self.content = content
    }

    public func render(into screen: inout Screen, at origin: Point, size: Size) {
        guard size.width >= 2, size.height >= 2 else { return }

        let r = origin.row
        let c = origin.col
        let w = size.width
        let h = size.height

        // Top border
        screen.put(row: r, col: c, text: String(style.topLeft), style: borderStyle)
        screen.horizontalLine(row: r, col: c + 1, length: w - 2, char: style.horizontal, style: borderStyle)
        screen.put(row: r, col: c + w - 1, text: String(style.topRight), style: borderStyle)

        // Title (centered in top border)
        if let title, !title.isEmpty {
            let maxTitleWidth = w - 4  // leave room for corners + spacing
            let truncated = title.count > maxTitleWidth ? String(title.prefix(maxTitleWidth)) : title
            let titleText = " \(truncated) "
            let titleCol = c + (w - titleText.count) / 2
            screen.put(row: r, col: titleCol, text: titleText, style: titleStyle)
        }

        // Side borders
        for row in (r + 1)..<(r + h - 1) {
            screen.put(row: row, col: c, text: String(style.vertical), style: borderStyle)
            screen.put(row: row, col: c + w - 1, text: String(style.vertical), style: borderStyle)
        }

        // Bottom border
        screen.put(row: r + h - 1, col: c, text: String(style.bottomLeft), style: borderStyle)
        screen.horizontalLine(row: r + h - 1, col: c + 1, length: w - 2, char: style.horizontal, style: borderStyle)
        screen.put(row: r + h - 1, col: c + w - 1, text: String(style.bottomRight), style: borderStyle)

        // Render content inside the box (inset by 1 on each side)
        let innerOrigin = Point(row: r + 1, col: c + 1)
        let innerSize = Size(width: w - 2, height: h - 2)
        content(&screen, innerOrigin, innerSize)
    }
}
