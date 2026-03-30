// StatusBar.swift — Bottom status bar showing keybinding hints
//
// Renders a styled bar at a given row showing available keyboard shortcuts.
// Automatically formats key-label pairs with consistent spacing.
//
// Usage:
//   let bar = StatusBar(items: [
//       StatusBar.Item(key: "↑↓", label: "Navigate"),
//       StatusBar.Item(key: "Enter", label: "Kill"),
//       StatusBar.Item(key: "q", label: "Quit"),
//   ])
//   bar.render(into: &screen, at: Point(row: 23, col: 0), size: Size(width: 80, height: 1))

// MARK: - Status Bar

public struct StatusBar: Widget {
    public let items: [Item]
    public let style: String       // Background style for the bar
    public let keyStyle: String    // Style for keybinding labels
    public let labelStyle: String  // Style for description text

    /// A single key-label pair displayed in the status bar
    public struct Item: Sendable {
        public let key: String
        public let label: String

        public init(key: String, label: String) {
            self.key = key
            self.label = label
        }
    }

    public init(
        items: [Item],
        style: String = ANSI.bg(.blue) + ANSI.fg(.white),
        keyStyle: String = ANSI.bold + ANSI.bg(.blue) + ANSI.fg(.brightWhite),
        labelStyle: String = ANSI.bg(.blue) + ANSI.fg(.white)
    ) {
        self.items = items
        self.style = style
        self.keyStyle = keyStyle
        self.labelStyle = labelStyle
    }

    public func render(into screen: inout Screen, at origin: Point, size: Size) {
        guard size.height >= 1 else { return }

        // Fill the full bar width with background
        screen.fillRow(origin.row, char: " ", style: style)

        // Render each key-label pair
        var col = origin.col + 1
        for item in items {
            let keyText = " \(item.key) "
            let labelText = " \(item.label)"

            // Don't overflow the screen
            guard col + keyText.count + labelText.count < origin.col + size.width else { break }

            screen.put(row: origin.row, col: col, text: keyText, style: keyStyle)
            col += keyText.count
            screen.put(row: origin.row, col: col, text: labelText, style: labelStyle)
            col += labelText.count + 2  // gap between items
        }
    }
}

// MARK: - Message Bar

/// A single-line message bar for showing status messages, errors, or search prompts.
public struct MessageBar: Widget {
    public let text: String
    public let style: String

    public init(text: String, style: String = ANSI.fg(.yellow)) {
        self.text = text
        self.style = style
    }

    public func render(into screen: inout Screen, at origin: Point, size: Size) {
        guard size.height >= 1 else { return }
        let display = fitString(text, width: size.width)
        screen.put(row: origin.row, col: origin.col, text: display, style: style)
    }
}
