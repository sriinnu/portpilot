// Screen.swift — Buffer-based screen renderer
//
// Provides a character buffer that widgets render into, then flushes to the terminal
// in one pass to avoid flicker. Supports styled text via ANSI escape codes.
//
// Usage:
//   var screen = Screen()
//   screen.put(row: 0, col: 0, text: "Hello", style: ANSI.bold + ANSI.fg(.cyan))
//   screen.render()

import Foundation

// MARK: - Styled Cell

/// A single character cell with optional ANSI styling
public struct Cell: Equatable {
    public var char: Character
    public var style: String  // ANSI escape prefix (empty = default)

    public init(char: Character = " ", style: String = "") {
        self.char = char
        self.style = style
    }

    public static let empty = Cell()
}

// MARK: - Screen Buffer

/// Double-buffered terminal screen. Widgets write into the buffer, then `render()`
/// flushes only changed cells to minimize flicker.
public struct Screen {
    public private(set) var width: Int
    public private(set) var height: Int

    /// Current frame buffer
    private var buffer: [[Cell]]
    /// Previous frame (for diff-based rendering)
    private var previous: [[Cell]]

    public init() {
        let size = Terminal.size()
        self.width = size.width
        self.height = size.height
        let emptyRow = [Cell](repeating: .empty, count: width)
        self.buffer = [[Cell]](repeating: emptyRow, count: height)
        self.previous = []
    }

    // MARK: - Resize

    /// Re-read terminal size and resize the buffer. Call on SIGWINCH.
    public mutating func resize() {
        let size = Terminal.size()
        self.width = size.width
        self.height = size.height
        clear()
        previous = []  // Force full redraw after resize
    }

    // MARK: - Clear

    /// Reset the entire buffer to empty cells
    public mutating func clear() {
        let emptyRow = [Cell](repeating: .empty, count: width)
        buffer = [[Cell]](repeating: emptyRow, count: height)
    }

    // MARK: - Writing to the Buffer

    /// Write a plain string at (row, col) with optional ANSI style prefix.
    /// Characters outside the screen bounds are silently clipped (both left and right).
    public mutating func put(row: Int, col: Int, text: String, style: String = "") {
        guard row >= 0, row < height else { return }
        var x = col
        for char in text {
            if x >= width { break }        // Past right edge — stop
            if x >= 0 {                    // On-screen — write cell
                buffer[row][x] = Cell(char: char, style: style)
            }
            x += 1                         // Before left edge — skip but advance
        }
    }

    /// Fill an entire row with a repeated character and style
    public mutating func fillRow(_ row: Int, char: Character = " ", style: String = "") {
        guard row >= 0, row < height else { return }
        for col in 0..<width {
            buffer[row][col] = Cell(char: char, style: style)
        }
    }

    /// Draw a horizontal line at the given row between col range
    public mutating func horizontalLine(row: Int, col: Int, length: Int, char: Character = "─", style: String = "") {
        guard row >= 0, row < height else { return }
        for x in col..<min(col + length, width) {
            guard x >= 0 else { continue }
            buffer[row][x] = Cell(char: char, style: style)
        }
    }

    // MARK: - Rendering

    /// Flush the buffer to the terminal. Uses diff-based rendering when possible
    /// to minimize output and reduce flicker.
    public mutating func render() {
        var output = ""
        output.reserveCapacity(width * height * 2)

        let fullRedraw = previous.isEmpty || previous.count != height

        for row in 0..<height {
            for col in 0..<width {
                let cell = buffer[row][col]
                let needsUpdate = fullRedraw || (row < previous.count && col < previous[row].count && previous[row][col] != cell)

                if needsUpdate {
                    output += ANSI.moveTo(row: row, col: col)
                    if !cell.style.isEmpty {
                        output += cell.style
                    }
                    output.append(cell.char)
                    if !cell.style.isEmpty {
                        output += ANSI.reset
                    }
                }
            }
        }

        if !output.isEmpty {
            Terminal.write(output)
            Terminal.flush()
        }

        // Swap buffers
        previous = buffer
    }

    /// Force a full redraw on the next render() call
    public mutating func invalidate() {
        previous = []
    }
}
