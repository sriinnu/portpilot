// Table.swift — Scrollable table widget with column definitions and row selection
//
// Renders a table with fixed column headers and scrollable rows. Supports
// selection highlighting, custom row styling, and configurable columns.
//
// Usage:
//   let columns: [TableColumn] = [
//       TableColumn(title: "PORT", width: 8),
//       TableColumn(title: "COMMAND", width: 20),
//   ]
//   let table = Table(columns: columns, rowCount: items.count, selectedRow: 2) { row, col in
//       row == 0 && col == 0 ? "8080" : "node"
//   }
//   table.render(into: &screen, at: origin, size: size)

// MARK: - Column Definition

/// Defines a single column in a table
public struct TableColumn: Sendable {
    public let title: String
    public let width: Int
    public let headerStyle: String
    public let alignment: Alignment

    public enum Alignment: Sendable {
        case left, right, center
    }

    public init(
        title: String,
        width: Int,
        headerStyle: String = ANSI.bold + ANSI.fg(.cyan),
        alignment: Alignment = .left
    ) {
        self.title = title
        self.width = width
        self.headerStyle = headerStyle
        self.alignment = alignment
    }
}

// MARK: - Table Widget

/// A scrollable table with column headers, selectable rows, and automatic scroll offset.
public struct Table: Widget {
    public let columns: [TableColumn]
    public let rowCount: Int
    public let selectedRow: Int?
    public let scrollOffset: Int
    public let selectedStyle: String       // ANSI style for the selected row
    public let alternateRowStyle: String?  // Optional style for zebra striping
    public let cellProvider: (Int, Int) -> (text: String, style: String)

    /// Create a table widget.
    ///
    /// - Parameters:
    ///   - columns: Column definitions (title, width, alignment)
    ///   - rowCount: Total number of data rows
    ///   - selectedRow: Currently selected row index (nil = no selection)
    ///   - scrollOffset: First visible row index (for scrolling)
    ///   - selectedStyle: ANSI style for highlighting selected row
    ///   - alternateRowStyle: Optional style for even-numbered rows
    ///   - cellProvider: Returns (text, style) for cell at (row, column)
    public init(
        columns: [TableColumn],
        rowCount: Int,
        selectedRow: Int? = nil,
        scrollOffset: Int = 0,
        selectedStyle: String = ANSI.inverse,
        alternateRowStyle: String? = nil,
        cellProvider: @escaping (Int, Int) -> (text: String, style: String)
    ) {
        self.columns = columns
        self.rowCount = rowCount
        self.selectedRow = selectedRow
        self.scrollOffset = scrollOffset
        self.selectedStyle = selectedStyle
        self.alternateRowStyle = alternateRowStyle
        self.cellProvider = cellProvider
    }

    public func render(into screen: inout Screen, at origin: Point, size: Size) {
        guard size.height >= 2 else { return } // Need room for header + at least 1 row

        // Render header row
        renderHeader(into: &screen, at: origin, width: size.width)

        // Separator line under header
        let sepRow = origin.row + 1
        screen.horizontalLine(row: sepRow, col: origin.col, length: size.width, char: "─", style: ANSI.dim)

        // Render visible data rows
        let visibleRows = size.height - 2  // subtract header + separator
        let endRow = min(scrollOffset + visibleRows, rowCount)

        for dataRow in scrollOffset..<endRow {
            let screenRow = origin.row + 2 + (dataRow - scrollOffset)
            renderRow(dataRow, into: &screen, row: screenRow, col: origin.col, width: size.width)
        }

        // Scroll indicator (right edge)
        if rowCount > visibleRows {
            renderScrollIndicator(into: &screen, at: origin, size: size, visibleRows: visibleRows)
        }
    }

    // MARK: - Header

    private func renderHeader(into screen: inout Screen, at origin: Point, width: Int) {
        var col = origin.col
        for column in columns {
            let text = formatCell(column.title, width: column.width, alignment: column.alignment)
            screen.put(row: origin.row, col: col, text: text, style: column.headerStyle)
            col += column.width + 1  // +1 for spacing between columns
        }
    }

    // MARK: - Data Rows

    private func renderRow(_ dataRow: Int, into screen: inout Screen, row: Int, col startCol: Int, width: Int) {
        let isSelected = dataRow == selectedRow

        // Background style for the full row
        if isSelected {
            // Fill entire row with selected background
            let rowText = String(repeating: " ", count: width)
            screen.put(row: row, col: startCol, text: rowText, style: selectedStyle)
        }

        // Render each cell
        var col = startCol
        for (colIdx, column) in columns.enumerated() {
            let (text, cellStyle) = cellProvider(dataRow, colIdx)
            let formatted = formatCell(text, width: column.width, alignment: column.alignment)
            let style = isSelected ? selectedStyle : cellStyle
            screen.put(row: row, col: col, text: formatted, style: style)
            col += column.width + 1
        }
    }

    // MARK: - Scroll Indicator

    /// Draws a thin scroll track on the right edge
    private func renderScrollIndicator(into screen: inout Screen, at origin: Point, size: Size, visibleRows: Int) {
        guard visibleRows > 0, rowCount > 0 else { return }

        let trackStart = origin.row + 2
        let trackHeight = visibleRows
        guard trackHeight > 1 else { return }

        // Thumb position and size
        let thumbSize = max(1, trackHeight * visibleRows / rowCount)
        let thumbPos = trackHeight * scrollOffset / rowCount

        for i in 0..<trackHeight {
            let row = trackStart + i
            let col = origin.col + size.width - 1
            let isThumb = i >= thumbPos && i < thumbPos + thumbSize
            screen.put(row: row, col: col, text: isThumb ? "█" : "░", style: ANSI.dim)
        }
    }

    // MARK: - Cell Formatting

    private func formatCell(_ text: String, width: Int, alignment: TableColumn.Alignment) -> String {
        switch alignment {
        case .left:   return fitString(text, width: width)
        case .right:  return rightAlign(text, width: width)
        case .center: return centerString(text, width: width)
        }
    }
}
