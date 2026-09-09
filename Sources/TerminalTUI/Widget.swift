// Widget.swift — Base protocol for all TUI components
//
// Every visual element conforms to `Widget` and renders itself into a `Screen`
// buffer at a given position. Widgets are composable — containers like Box
// render child widgets inside themselves.
//
// Usage:
//   struct MyWidget: Widget {
//       func render(into screen: inout Screen, at origin: Point, size: Size) { ... }
//   }

// MARK: - Geometry Types

/// A point in screen coordinates (0-indexed, top-left origin)
public struct Point: Equatable, Sendable {
    public var row: Int
    public var col: Int

    public init(row: Int = 0, col: Int = 0) {
        self.row = row
        self.col = col
    }

    public static let zero = Point()
}

/// A rectangular size
public struct Size: Equatable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int = 0, height: Int = 0) {
        self.width = width
        self.height = height
    }

    public static let zero = Size()
}

/// A positioned rectangle — useful for layout calculations
public struct Rect: Equatable, Sendable {
    public var origin: Point
    public var size: Size

    public init(origin: Point = .zero, size: Size = .zero) {
        self.origin = origin
        self.size = size
    }

    public var row: Int { origin.row }
    public var col: Int { origin.col }
    public var width: Int { size.width }
    public var height: Int { size.height }
    public var maxRow: Int { origin.row + size.height }
    public var maxCol: Int { origin.col + size.width }
}

// MARK: - Widget Protocol

/// Conforming types can render themselves into a terminal screen buffer.
public protocol Widget {
    /// Render this widget into the screen buffer at the given position and size.
    func render(into screen: inout Screen, at origin: Point, size: Size)
}

// MARK: - Text Helpers
//
// All of these measure display columns (see TextWidth), not character count —
// a CJK glyph or emoji takes two terminal columns, and pretending otherwise
// makes aligned columns drift.

/// Pad or truncate a string to exactly `width` display columns.
/// Returns empty string for zero or negative width.
public func fitString(_ string: String, width: Int, pad: Character = " ") -> String {
    guard width > 0 else { return "" }
    let truncated = TextWidth.truncate(string, toWidth: width)
    let padCount = width - TextWidth.displayWidth(truncated)
    return padCount > 0 ? truncated + String(repeating: pad, count: padCount) : truncated
}

/// Right-align a string within `width` display columns.
/// Returns empty string for zero or negative width.
public func rightAlign(_ string: String, width: Int) -> String {
    guard width > 0 else { return "" }
    let truncated = TextWidth.truncate(string, toWidth: width)
    let padCount = width - TextWidth.displayWidth(truncated)
    return padCount > 0 ? String(repeating: " ", count: padCount) + truncated : truncated
}

/// Center a string within `width` display columns.
/// Returns empty string for zero or negative width.
public func centerString(_ string: String, width: Int) -> String {
    guard width > 0 else { return "" }
    let truncated = TextWidth.truncate(string, toWidth: width)
    let padTotal = width - TextWidth.displayWidth(truncated)
    guard padTotal > 0 else { return truncated }
    let left = padTotal / 2
    let right = padTotal - left
    return String(repeating: " ", count: left) + truncated + String(repeating: " ", count: right)
}
