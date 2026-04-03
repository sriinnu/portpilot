// CronjobDetailScreen.swift — Detail view for a cronjob entry in PortPilot TUI
//
// Shows full cronjob details: schedule, command, source, and next N run times.

import Foundation
import TerminalTUI
import PortManagerLib

struct CronjobDetailScreen: TUIScreen {

    private let cronjob: CronjobEntry
    private let portManager = PortManager()

    init(cronjob: CronjobEntry) {
        self.cronjob = cronjob
    }

    mutating func render(into screen: inout Screen) {
        let w = screen.width
        let h = screen.height
        guard h >= 10 else { return }

        let title = " Cronjob Detail "
        screen.put(row: 0, col: 0, text: title, style: ANSI.bold + ANSI.bg(.blue) + ANSI.fg(.brightWhite))
        screen.horizontalLine(row: 1, col: 0, length: w, char: "─", style: ANSI.dim)

        var row = 3

        // Schedule
        renderField(into: &screen, row: &row, label: "Schedule", value: cronjob.scheduleHuman ?? cronjob.schedule, width: w)
        renderField(into: &screen, row: &row, label: "Raw", value: cronjob.schedule, width: w)

        // Command
        let commandLines = wrapText(cronjob.command, width: max(w - 20, 20))
        for (i, line) in commandLines.enumerated() {
            let label = i == 0 ? "Command" : ""
            renderField(into: &screen, row: &row, label: label, value: line, width: w)
        }

        // User
        if let user = cronjob.user {
            renderField(into: &screen, row: &row, label: "User", value: user, width: w)
        }

        // Source
        renderField(into: &screen, row: &row, label: "Source", value: cronjob.source, width: w)

        row += 1

        // Next runs
        screen.put(row: row, col: 0, text: " Next Runs ", style: ANSI.bold + ANSI.fg(.brightCyan))
        row += 1

        let nextRuns = upcomingRuns(count: 5)
        for (i, date) in nextRuns.enumerated() {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, MMM d  HH:mm:ss"
            let relative = relativeTime(from: date)
            let line = "  \(i + 1). \(formatter.string(from: date))  (\(relative))"
            screen.put(row: row, col: 0, text: fitString(line, width: w), style: ANSI.fg(.white))
            row += 1
        }

        // Bottom bar
        let barRow = h - 2
        screen.horizontalLine(row: barRow, col: 0, length: w, char: "─", style: ANSI.dim)
        let statusBar = StatusBar(items: [
            StatusBar.Item(key: "Esc", label: "Back"),
        ])
        statusBar.render(into: &screen, at: Point(row: barRow + 1, col: 0), size: TerminalTUI.Size(width: w, height: 1))
    }

    mutating func handleKey(_ key: KeyEvent) -> ScreenAction {
        switch key {
        case .escape, .char("q"), .char("Q"), .ctrlC:
            return .pop
        default:
            break
        }
        return .continue
    }

    mutating func onResize(width: Int, height: Int) {}

    // MARK: - Helpers

    private func renderField(into screen: inout Screen, row: inout Int, label: String, value: String, width: Int) {
        if label.isEmpty {
            screen.put(row: row, col: 4, text: fitString(value, width: width - 4), style: ANSI.fg(.white))
        } else {
            let labelStr = "  \(label):"
            screen.put(row: row, col: 0, text: labelStr, style: ANSI.bold + ANSI.fg(.brightYellow))
            screen.put(row: row, col: labelStr.count, text: " ", style: "")
            screen.put(row: row, col: labelStr.count + 1, text: fitString(value, width: width - labelStr.count - 1), style: ANSI.fg(.white))
        }
        row += 1
    }

    private func wrapText(_ text: String, width: Int) -> [String] {
        guard text.count > width else { return [text] }
        var lines: [String] = []
        var remaining = text
        while remaining.count > width {
            let index = remaining.index(remaining.startIndex, offsetBy: width)
            lines.append(String(remaining[..<index]))
            remaining = String(remaining[index...]).trimmingCharacters(in: .whitespaces)
        }
        if !remaining.isEmpty {
            lines.append(remaining)
        }
        return lines
    }

    private func upcomingRuns(count: Int) -> [Date] {
        guard let nextRun = cronjob.nextRun else { return [] }
        var runs: [Date] = [nextRun]
        var current = nextRun

        for _ in 1..<count {
            guard let next = portManager.nextCronRun(after: current, schedule: cronjob.schedule) else { break }
            if runs.contains(next) { break } // avoid infinite loops
            runs.append(next)
            current = next
        }

        return runs
    }

    private func relativeTime(from date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval < 0 { return "past" }
        if interval < 60 { return "in \(Int(interval))s" }
        if interval < 3600 { return "in \(Int(interval / 60))m" }
        if interval < 86400 { return "in \(Int(interval / 3600))h" }
        return "in \(Int(interval / 86400))d"
    }
}
