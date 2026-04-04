// DashboardView.swift — Rich dashboard with visual metrics
//
// Displays summary cards, ASCII bar charts, and network activity.

import Foundation
import TerminalTUI
import PortManagerLib

// MARK: - Dashboard Metrics

struct DashboardMetrics {
    var totalProcesses: Int
    var totalPorts: Int
    var totalConnections: Int
    var totalSockets: Int
    var cpuUsage: Double
    var memoryUsage: Double
    var networkInBytes: UInt64
    var networkOutBytes: UInt64
    var connectionRate: Int  // connections per second
    var uptime: TimeInterval

    static func empty() -> DashboardMetrics {
        DashboardMetrics(
            totalProcesses: 0,
            totalPorts: 0,
            totalConnections: 0,
            totalSockets: 0,
            cpuUsage: 0,
            memoryUsage: 0,
            networkInBytes: 0,
            networkOutBytes: 0,
            connectionRate: 0,
            uptime: 0
        )
    }
}

// MARK: - ASCII Progress Bar

struct ASCIIProgressBar {
    var value: Double  // 0.0 to 1.0
    var width: Int
    var label: String
    var showPercentage: Bool
    var color: ANSI.Color

    func render() -> String {
        let filledWidth = Int(Double(width) * min(value, 1.0))
        let emptyWidth = width - filledWidth

        let bar: String
        if value < 0.3 {
            bar = String(repeating: "░", count: filledWidth) + String(repeating: " ", count: emptyWidth)
        } else if value < 0.7 {
            bar = String(repeating: "▒", count: filledWidth) + String(repeating: " ", count: emptyWidth)
        } else {
            bar = String(repeating: "█", count: filledWidth) + String(repeating: " ", count: emptyWidth)
        }

        let percentage = showPercentage ? String(format: " %3.0f%%", value * 100) : ""
        return "\(label): [\(bar)]\(percentage)"
    }
}

// MARK: - ASCII Sparkline

struct ASCIISparkline {
    var values: [Double]  // Array of 0.0-1.0 values
    var width: Int
    var height: Int
    var color: ANSI.Color

    func render() -> [String] {
        guard !values.isEmpty else { return [] }

        let chars = [" ", "⡀", "⡁", "⡂", "⡃", "⡄", "⡅", "⡆", "⡇", "⡈"]
        var lines: [String] = []

        for row in 0..<height {
            var line = ""
            let threshold = Double(height - row - 1) / Double(height)

            for i in 0..<min(values.count, width) {
                let normalizedValue = values[i]
                let charIndex: Int
                if normalizedValue <= threshold {
                    charIndex = 0  // space
                } else {
                    let relativeHeight = (normalizedValue - threshold) / (1.0 - threshold)
                    charIndex = min(Int(relativeHeight * 9) + 1, 9)
                }
                line += chars[charIndex]
            }
            lines.append(line)
        }

        return lines
    }
}

// MARK: - Dashboard View

struct DashboardView {
    var metrics: DashboardMetrics
    var processes: [PortProcess]
    var connections: [EstablishedConnection]

    private let portManager = PortManager()

    mutating func render(into screen: inout Screen, width: Int, height: Int) {
        let theme = TUIThemeManager.shared
        let colors = theme.colors
        let borders = theme.borders

        var row = 0

        // ═══════════════════════════════════════════════════════════════
        // DYNAMIC ISLAND HEADER
        // ═══════════════════════════════════════════════════════════════

        renderDynamicIsland(into: &screen, row: row, width: width)
        row += 3

        // ═══════════════════════════════════════════════════════════════
        // SUMMARY CARDS ROW
        // ═══════════════════════════════════════════════════════════════

        let cardWidth = (width - 6) / 4
        if cardWidth >= 2 {
            renderSummaryCard(into: &screen, row: row, col: 1, width: cardWidth,
                             title: "PROCESSES", value: "\(metrics.totalProcesses)",
                             icon: "◉", color: colors.primary)
            renderSummaryCard(into: &screen, row: row, col: 2 + cardWidth, width: cardWidth,
                             title: "PORTS", value: "\(metrics.totalPorts)",
                             icon: "●", color: colors.secondary)
            renderSummaryCard(into: &screen, row: row, col: 3 + cardWidth * 2, width: cardWidth,
                             title: "CONNECTIONS", value: "\(metrics.totalConnections)",
                             icon: "◆", color: colors.accent)
            renderSummaryCard(into: &screen, row: row, col: 4 + cardWidth * 3, width: cardWidth,
                             title: "SOCKETS", value: "\(metrics.totalSockets)",
                             icon: "○", color: colors.success)

            row += 4
        }

        // ═══════════════════════════════════════════════════════════════
        // CPU & MEMORY USAGE BARS
        // ═══════════════════════════════════════════════════════════════

        renderSectionHeader(into: &screen, row: row, width: width, title: "SYSTEM RESOURCES")
        row += 1

        // CPU Usage Bar
        let cpuBar = ASCIIProgressBar(
            value: metrics.cpuUsage / 100.0,
            width: width - 20,
            label: "CPU",
            showPercentage: true,
            color: metrics.cpuUsage > 80 ? colors.error : (metrics.cpuUsage > 50 ? colors.warning : colors.success)
        )
        screen.put(row: row, col: 2, text: cpuBar.render(), style: theme.fonts.bodyStyle)
        row += 1

        // Memory Usage Bar
        let memBar = ASCIIProgressBar(
            value: metrics.memoryUsage / 100.0,
            width: width - 20,
            label: "MEM",
            showPercentage: true,
            color: metrics.memoryUsage > 80 ? colors.error : (metrics.memoryUsage > 50 ? colors.warning : colors.accent)
        )
        screen.put(row: row, col: 2, text: memBar.render(), style: theme.fonts.bodyStyle)
        row += 2

        // ═══════════════════════════════════════════════════════════════
        // NETWORK ACTIVITY SPARKLINE
        // ═══════════════════════════════════════════════════════════════

        renderSectionHeader(into: &screen, row: row, width: width, title: "NETWORK ACTIVITY")
        row += 1

        // Network stats
        let inBytes = formatBytes(Int64(metrics.networkInBytes))
        let outBytes = formatBytes(Int64(metrics.networkOutBytes))
        let rateStr = metrics.connectionRate > 0 ? " (\(metrics.connectionRate)/s)" : ""

        screen.put(row: row, col: 2, text: "↓ IN: \(inBytes)", style: ANSI.fg(colors.success))
        screen.put(row: row, col: width / 2, text: "↑ OUT: \(outBytes)\(rateStr)", style: ANSI.fg(colors.accent))
        row += 1

        // ASCII Sparkline for network activity
        let sparklineValues = generateSparklineData()
        let sparkline = ASCIISparkline(
            values: sparklineValues,
            width: width - 4,
            height: 3,
            color: colors.accent
        )
        let sparklineLines = sparkline.render()
        for (index, line) in sparklineLines.enumerated() {
            screen.put(row: row + index, col: 2, text: line, style: ANSI.fg(colors.accent))
        }
        row += 4

        // ═══════════════════════════════════════════════════════════════
        // TOP PROCESSES TABLE (mini)
        // ═══════════════════════════════════════════════════════════════

        renderSectionHeader(into: &screen, row: row, width: width, title: "TOP PROCESSES")
        row += 1

        // Table header
        screen.put(row: row, col: 2, text: "PID", style: theme.fonts.headerStyle)
        screen.put(row: row, col: 10, text: "PORT", style: theme.fonts.headerStyle)
        screen.put(row: row, col: 18, text: "CPU%", style: theme.fonts.headerStyle)
        screen.put(row: row, col: 26, text: "MEM", style: theme.fonts.headerStyle)
        screen.put(row: row, col: 34, text: "PROCESS", style: theme.fonts.headerStyle)
        row += 1

        // Top 5 processes
        let topProcesses = processes.sorted { $0.cpuUsage ?? 0 > $1.cpuUsage ?? 1 }.prefix(5)
        for proc in topProcesses {
            let cpuColor = (proc.cpuUsage ?? 0) > 80 ? colors.error : ((proc.cpuUsage ?? 0) > 50 ? colors.warning : colors.text)
            let memColor = (proc.memoryMB ?? 0) > 80 ? colors.error : ((proc.memoryMB ?? 0) > 50 ? colors.warning : colors.text)

            screen.put(row: row, col: 2, text: "\(proc.pid)", style: ANSI.fg(colors.textMuted))
            screen.put(row: row, col: 10, text: "\(proc.port)", style: ANSI.fg(colors.accent))
            screen.put(row: row, col: 18, text: String(format: "%5.1f", proc.cpuUsage ?? 0), style: ANSI.fg(cpuColor))
            screen.put(row: row, col: 26, text: formatMemory(proc.memoryMB ?? 0), style: ANSI.fg(memColor))
            screen.put(row: row, col: 34, text: fitString(proc.command, width: width - 36), style: theme.fonts.bodyStyle)
            row += 1
        }

        row += 1

        // ═══════════════════════════════════════════════════════════════
        // TIME-BASED METRICS
        // ═══════════════════════════════════════════════════════════════

        renderSectionHeader(into: &screen, row: row, width: width, title: "ACTIVITY TIMELINE")
        row += 1

        // Activity histogram (last 10 minutes)
        let histogram = generateActivityHistogram()
        screen.put(row: row, col: 2, text: "10m  │\(histogram)│ now", style: theme.fonts.mutedStyle)
        row += 2
    }

    // MARK: - Rendering Helpers

    private func renderDynamicIsland(into screen: inout Screen, row: Int, width: Int) {
        let theme = TUIThemeManager.shared
        let colors = theme.colors
        let borders = theme.borders

        // Convert borders to strings
        let vertical = String(borders.vertical)
        let horizontal = String(borders.horizontal)
        let topLeft = String(borders.topLeft)
        let topRight = String(borders.topRight)
        let bottomLeft = String(borders.bottomLeft)
        let bottomRight = String(borders.bottomRight)

        // Top border with Dynamic Island shape
        let islandWidth = min(width - 4, 60)
        let islandStart = (width - islandWidth) / 2

        // Notch cutout effect
        let notchWidth = 20
        let notchStart = (width - notchWidth) / 2

        // Row 0: Top border with notch cutout
        screen.put(row: row, col: 0, text: String(repeating: topLeft, count: notchStart), style: ANSI.fg(colors.border))
        screen.put(row: row, col: notchStart + notchWidth, text: String(repeating: topRight, count: width - notchStart - notchWidth), style: ANSI.fg(colors.border))

        // Row 1: Island content with notch
        let title = " PortPilot "
        let platform = platformLabel()
        let centeredTitle = centerString(title, width: islandWidth - 4)
        let timeStr = formatTime(Date())

        // Left padding
        screen.put(row: row + 1, col: 0, text: vertical, style: ANSI.fg(colors.border))
        screen.put(row: row + 1, col: 1, text: String(repeating: " ", count: islandStart - 1), style: "")

        // Island left border
        screen.put(row: row + 1, col: islandStart, text: vertical, style: ANSI.fg(colors.border))

        // Island content
        screen.put(row: row + 1, col: islandStart + 1, text: centeredTitle, style: theme.fonts.titleStyle)

        // Platform indicator
        screen.put(row: row + 1, col: islandStart + islandWidth - platform.count - 2, text: platform, style: theme.fonts.mutedStyle)

        // Island right border
        screen.put(row: row + 1, col: islandStart + islandWidth - 1, text: vertical, style: ANSI.fg(colors.border))

        // Right padding
        screen.put(row: row + 1, col: islandStart + islandWidth, text: String(repeating: " ", count: width - islandStart - islandWidth - 1), style: "")
        screen.put(row: row + 1, col: width - 1, text: vertical, style: ANSI.fg(colors.border))

        // Row 2: Bottom border
        screen.put(row: row + 2, col: 0, text: bottomLeft, style: ANSI.fg(colors.border))
        screen.put(row: row + 2, col: 1, text: String(repeating: horizontal, count: islandStart - 1), style: ANSI.fg(colors.border))
        screen.put(row: row + 2, col: islandStart, text: bottomRight, style: ANSI.fg(colors.border))
        screen.put(row: row + 2, col: islandStart + 1, text: String(repeating: horizontal, count: islandWidth - 2), style: ANSI.fg(colors.border))
        screen.put(row: row + 2, col: islandStart + islandWidth - 1, text: bottomLeft, style: ANSI.fg(colors.border))
        screen.put(row: row + 2, col: islandStart + islandWidth, text: String(repeating: horizontal, count: width - islandStart - islandWidth - 1), style: ANSI.fg(colors.border))
        screen.put(row: row + 2, col: width - 1, text: bottomRight, style: ANSI.fg(colors.border))

        // Time display on bottom border
        let timePos = width - timeStr.count - 2
        screen.put(row: row + 2, col: timePos, text: timeStr, style: theme.fonts.mutedStyle)
    }

    private func renderSummaryCard(into screen: inout Screen, row: Int, col: Int, width: Int,
                                    title: String, value: String, icon: String, color: ANSI.Color) {
        let theme = TUIThemeManager.shared
        let borders = theme.borders

        // Card border - Convert Character to String
        let topLeft = String(borders.topLeft)
        let topRight = String(borders.topRight)
        let bottomLeft = String(borders.bottomLeft)
        let bottomRight = String(borders.bottomRight)
        let horizontal = String(borders.horizontal)
        let vertical = String(borders.vertical)

        screen.put(row: row, col: col, text: topLeft + String(repeating: horizontal, count: width - 2) + topRight, style: ANSI.fg(color))
        screen.put(row: row + 1, col: col, text: vertical, style: ANSI.fg(color))
        screen.put(row: row + 1, col: col + width - 1, text: vertical, style: ANSI.fg(color))
        screen.put(row: row + 2, col: col, text: vertical, style: ANSI.fg(color))
        screen.put(row: row + 2, col: col + width - 1, text: vertical, style: ANSI.fg(color))
        screen.put(row: row + 3, col: col, text: bottomLeft + String(repeating: horizontal, count: width - 2) + bottomRight, style: ANSI.fg(color))

        // Card content
        let titleCentered = centerString(title, width: width - 4)
        screen.put(row: row + 1, col: col + 1, text: titleCentered, style: theme.fonts.mutedStyle)
        screen.put(row: row + 2, col: col + 2, text: icon + " " + value, style: theme.fonts.headerStyle + ANSI.fg(color))
    }

    private func renderSectionHeader(into screen: inout Screen, row: Int, width: Int, title: String) {
        let theme = TUIThemeManager.shared
        let colors = theme.colors
        let borders = theme.borders

        guard width > 0 else { return }

        let style = theme.fonts.mutedStyle + ANSI.fg(colors.border)
        let sideLineCount = 3
        let sideLine = String(repeating: borders.horizontal, count: sideLineCount)
        let minimumDecoratedWidth = (sideLineCount * 2) + 2 // 3 left + 3 right + spaces around title

        if width < minimumDecoratedWidth {
            screen.put(
                row: row,
                col: 0,
                text: String(repeating: borders.horizontal, count: width),
                style: style
            )
            return
        }

        let maxTitleCount = max(0, width - (sideLineCount * 2) - 2)
        let displayTitle: String
        if title.count <= maxTitleCount {
            displayTitle = title
        } else if maxTitleCount >= 3 {
            displayTitle = String(title.prefix(maxTitleCount - 3)) + "..."
        } else {
            displayTitle = String(title.prefix(maxTitleCount))
        }

        let paddedTitle = " \(displayTitle) "
        let endLineCount = max(0, width - paddedTitle.count - (sideLineCount * 2))
        let endLine = String(repeating: borders.horizontal, count: endLineCount)

        screen.put(row: row, col: 0, text: sideLine + paddedTitle + endLine + sideLine, style: style)
    }

    // MARK: - Data Helpers

    private func generateSparklineData() -> [Double] {
        // Return a neutral placeholder until real historical samples are wired in.
        // Avoid generating random values, which would imply unstable/fictional trends.
        return Array(repeating: 0.0, count: 40)
    }

    private func generateActivityHistogram(width: Int = 80) -> String {
        // Return an empty placeholder histogram instead of random activity bars.
        // This avoids implying real network activity when no historical data exists.
        let histogramWidth = max(0, width - 20)
        return String(repeating: " ", count: histogramWidth)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        return String(format: "%.1f\(units[unitIndex])", value)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func platformLabel() -> String {
        switch Platform.current {
        case .macOS: return "macOS"
        case .linux: return "Linux"
        case .wsl: return "WSL"
        case .windows: return "Windows"
        }
    }
}

// MARK: - Helper Functions

private func centerString(_ str: String, width: Int) -> String {
    let padding = max(0, (width - str.count) / 2)
    return String(repeating: " ", count: padding) + str + String(repeating: " ", count: width - str.count - padding)
}

private func fitString(_ str: String, width: Int) -> String {
    if str.count <= width { return str }
    return String(str.prefix(width - 3)) + "..."
}
