// ConnectionDetailScreen.swift — Detail view for a connection in PortPilot TUI
//
// Shows connection details: local/remote addresses, process info, state.

import Foundation
import TerminalTUI
import PortManagerLib

struct ConnectionDetailScreen: TUIScreen {

    private let connection: EstablishedConnection
    private let portManager = PortManager()
    private var confirmingKill: Bool = false

    init(connection: EstablishedConnection) {
        self.connection = connection
    }

    mutating func render(into screen: inout Screen) {
        let w = screen.width
        let h = screen.height
        guard h >= 10 else { return }

        let title = " Connection Detail "
        screen.put(row: 0, col: 0, text: title, style: ANSI.bold + ANSI.bg(.blue) + ANSI.fg(.brightWhite))
        screen.horizontalLine(row: 1, col: 0, length: w, char: "─", style: ANSI.dim)

        var row = 3

        // Remote address
        renderField(into: &screen, row: &row, label: "Remote", value: connection.remoteAddress, width: w)
        renderField(into: &screen, row: &row, label: "Local", value: connection.localAddress, width: w)
        renderField(into: &screen, row: &row, label: "State", value: connection.state, width: w)
        row += 1

        // Process info
        renderField(into: &screen, row: &row, label: "Process", value: connection.processName, width: w)
        renderField(into: &screen, row: &row, label: "PID", value: "\(connection.pid)", width: w)
        renderField(into: &screen, row: &row, label: "User", value: connection.user, width: w)

        // Bottom bar
        let barRow = h - 2
        screen.horizontalLine(row: barRow, col: 0, length: w, char: "─", style: ANSI.dim)

        let items: [StatusBar.Item]
        let msgRow = barRow + 1
        if confirmingKill {
            items = [
                StatusBar.Item(key: "y", label: "Confirm Kill"),
                StatusBar.Item(key: "n/Esc", label: "Cancel"),
            ]
            let msg = "Kill \(connection.processName) (pid \(connection.pid))? [y/n]"
            screen.put(row: msgRow, col: 0, text: fitString(msg, width: w), style: ANSI.bold + ANSI.fg(.red))
        } else {
            items = [
                StatusBar.Item(key: "Esc", label: "Back"),
                StatusBar.Item(key: "x", label: "Kill Process"),
            ]
        }

        let statusBar = StatusBar(items: items)
        statusBar.render(into: &screen, at: Point(row: msgRow, col: 0), size: TerminalTUI.Size(width: w, height: 1))
    }

    mutating func handleKey(_ key: KeyEvent) -> ScreenAction {
        if confirmingKill {
            switch key {
            case .char("y"), .char("Y"):
                confirmingKill = false
                return killProcess()
            case .char("n"), .char("N"), .escape:
                confirmingKill = false
            default:
                break
            }
            return .continue
        }

        switch key {
        case .escape, .char("q"), .char("Q"), .ctrlC:
            return .pop
        case .char("x"), .char("X"):
            confirmingKill = true
        default:
            break
        }
        return .continue
    }

    mutating func onResize(width: Int, height: Int) {}

    private func killProcess() -> ScreenAction {
        let pid = connection.pid

        do {
            try portManager.killProcessByPID(pid, force: false)
            return .pop
        } catch {
            do {
                try portManager.killProcessByPID(pid, force: true)
                return .pop
            } catch {
                return .continue
            }
        }
    }

    private func renderField(into screen: inout Screen, row: inout Int, label: String, value: String, width: Int) {
        let labelStr = "  \(label):"
        screen.put(row: row, col: 0, text: labelStr, style: ANSI.bold + ANSI.fg(.brightYellow))
        screen.put(row: row, col: labelStr.count, text: " ", style: "")
        screen.put(row: row, col: labelStr.count + 1, text: fitString(value, width: width - labelStr.count - 1), style: ANSI.fg(.white))
        row += 1
    }
}
