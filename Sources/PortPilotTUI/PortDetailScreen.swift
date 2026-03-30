// PortDetailScreen.swift — Detailed view for a single port/process
//
// Shows full process information, connections, and available actions
// for a selected port. Navigated to from the port list via 'i' key.

import Foundation
import TerminalTUI
import PortManagerLib

// MARK: - Port Detail Screen

struct PortDetailScreen: TUIScreen {

    // MARK: - State

    private let process: PortProcess
    private let portManager: PortManager
    private var connections: [PortConnection] = []
    private var errorMessage: String?

    // MARK: - Init

    init(process: PortProcess, portManager: PortManager) {
        self.process = process
        self.portManager = portManager
        loadConnections()
    }

    private mutating func loadConnections() {
        guard !process.isUnixSocket else { return }
        do {
            connections = try portManager.getConnections(for: process.port)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Rendering

    func render(into screen: inout Screen) {
        let w = screen.width
        let h = screen.height

        // Header
        let title = process.isUnixSocket
            ? " Unix Socket — PID \(process.pid) "
            : " Port \(process.port) — \(process.command) "
        screen.put(row: 0, col: 0, text: fitString(centerString(title, width: w), width: w),
                   style: ANSI.bold + ANSI.bg(.blue) + ANSI.fg(.brightWhite))

        // Process info box — dynamic height based on available fields
        let boxWidth = min(w - 4, 70)
        let fieldCount = countInfoFields()
        let boxHeight = fieldCount + 2  // +2 for border top/bottom
        let box = Box(title: "Process Info", style: .rounded, borderStyle: ANSI.fg(.cyan)) { screen, origin, size in
            renderProcessInfo(into: &screen, at: origin, size: size)
        }
        box.render(into: &screen, at: Point(row: 2, col: 2), size: TerminalTUI.Size(width: boxWidth, height: boxHeight))

        // Connections box (network ports only)
        if !process.isUnixSocket {
            let connBoxTop = 2 + boxHeight + 1
            let connBoxHeight = max(min(h - connBoxTop - 3, max(connections.count + 3, 5)), 0)
            guard connBoxHeight >= 3 else { return }  // Not enough room
            let connBox = Box(title: "Connections (\(connections.count))", style: .rounded, borderStyle: ANSI.fg(.cyan)) { screen, origin, size in
                renderConnections(into: &screen, at: origin, size: size)
            }
            connBox.render(into: &screen, at: Point(row: connBoxTop, col: 2),
                           size: TerminalTUI.Size(width: boxWidth, height: connBoxHeight))
        }

        // Error message
        if let errorMessage {
            screen.put(row: h - 3, col: 2, text: "Error: \(errorMessage)", style: ANSI.fg(.red))
        }

        // Bottom status bar — use 'x' for kill to avoid conflict with 'k' navigation
        let bar = StatusBar(items: [
            StatusBar.Item(key: "Esc", label: "Back"),
            StatusBar.Item(key: "x", label: "Kill"),
            StatusBar.Item(key: "X", label: "Force Kill"),
            StatusBar.Item(key: "q", label: "Quit"),
        ])
        bar.render(into: &screen, at: Point(row: h - 2, col: 0), size: TerminalTUI.Size(width: w, height: 1))
    }

    // MARK: - Process Info

    /// Count how many info fields will be displayed (for dynamic box sizing)
    private func countInfoFields() -> Int {
        var count = 0
        if !process.isUnixSocket { count += 2 }  // Port, Protocol
        count += 3  // PID, User, Command (always shown)
        if process.fullCommand != nil { count += 1 }
        if process.parentPID != nil   { count += 1 }
        if process.startTime != nil   { count += 1 }
        if process.cpuUsage != nil    { count += 1 }
        if process.memoryMB != nil    { count += 1 }
        if process.processPath != nil { count += 1 }
        if process.workingDirectory != nil { count += 1 }
        if process.socketPath != nil  { count += 1 }
        return count
    }

    private func renderProcessInfo(into screen: inout Screen, at origin: Point, size: TerminalTUI.Size) {
        let labelStyle = ANSI.bold + ANSI.fg(.cyan)
        let valueStyle = ANSI.fg(.white)
        let labelWidth = 12
        var row = origin.row

        // Render a single label: value pair
        func field(_ label: String, _ value: String) {
            guard row < origin.row + size.height else { return }
            screen.put(row: row, col: origin.col, text: fitString(label + ":", width: labelWidth), style: labelStyle)
            let maxVal = size.width - labelWidth - 1
            screen.put(row: row, col: origin.col + labelWidth, text: fitString(value, width: maxVal), style: valueStyle)
            row += 1
        }

        if !process.isUnixSocket {
            field("Port", "\(process.port)")
            field("Protocol", process.protocolName.uppercased())
        }
        field("PID", "\(process.pid)")
        field("User", process.user)
        field("Command", process.command)

        if let fullCmd = process.fullCommand {
            field("Full Cmd", fullCmd)
        }
        if let parentPID = process.parentPID {
            field("Parent PID", "\(parentPID)")
        }
        if let startTime = process.startTime {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            field("Started", formatter.string(from: startTime))
        }
        if let cpu = process.cpuUsage {
            field("CPU", String(format: "%.1f%%", cpu))
        }
        if let mem = process.memoryMB {
            field("Memory", formatMemory(mem))  // Uses shared formatMemory() from PortListScreen.swift
        }
        if let path = process.processPath {
            field("Path", path)
        }
        if let cwd = process.workingDirectory {
            field("Work Dir", cwd)
        }
        if let socketPath = process.socketPath {
            field("Socket", socketPath)
        }
    }

    // MARK: - Connections

    private func renderConnections(into screen: inout Screen, at origin: Point, size: TerminalTUI.Size) {
        if connections.isEmpty {
            screen.put(row: origin.row, col: origin.col, text: "No active connections", style: ANSI.dim)
            return
        }

        // Header
        let hdrStyle = ANSI.bold + ANSI.fg(.cyan)
        screen.put(row: origin.row, col: origin.col,
                   text: fitString("LOCAL ADDRESS", width: 22), style: hdrStyle)
        screen.put(row: origin.row, col: origin.col + 23,
                   text: fitString("REMOTE ADDRESS", width: 22), style: hdrStyle)
        screen.put(row: origin.row, col: origin.col + 46,
                   text: "STATE", style: hdrStyle)

        // Connection rows
        let maxRows = max(size.height - 1, 0)
        for (i, conn) in connections.prefix(maxRows).enumerated() {
            let row = origin.row + 1 + i
            screen.put(row: row, col: origin.col,
                       text: fitString(conn.localAddress, width: 22), style: ANSI.fg(.white))
            screen.put(row: row, col: origin.col + 23,
                       text: fitString(conn.remoteAddress, width: 22), style: ANSI.fg(.white))
            screen.put(row: row, col: origin.col + 46,
                       text: conn.state, style: stateStyle(conn.state))
        }
    }

    // MARK: - Key Handling

    mutating func handleKey(_ key: KeyEvent) -> ScreenAction {
        switch key {
        case .escape:
            return .pop

        case .char("q"), .char("Q"):
            return .quit

        // Use 'x' for kill (not 'k') to avoid conflict with vim-style 'k' navigation
        case .char("x"):
            return killProcess(force: false)

        case .char("X"):
            return killProcess(force: true)

        case .ctrlC:
            return .quit

        default:
            return .continue
        }
    }

    // MARK: - Actions

    private mutating func killProcess(force: Bool) -> ScreenAction {
        do {
            if process.isUnixSocket {
                // Unix sockets have port=0; kill by PID directly
                let signal = force ? "KILL" : "TERM"
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/kill")
                task.arguments = ["-s", signal, "\(process.pid)"]
                try task.run()
                task.waitUntilExit()
            } else {
                try portManager.killProcessOnPort(process.port, force: force)
            }
            return .pop
        } catch {
            errorMessage = error.localizedDescription
            return .continue
        }
    }

    // MARK: - Helpers

    /// Color connection states for quick scanning
    private func stateStyle(_ state: String) -> String {
        switch state.uppercased() {
        case "ESTABLISHED": return ANSI.fg(.green)
        case "LISTEN":      return ANSI.fg(.cyan)
        case "TIME_WAIT":   return ANSI.fg(.yellow)
        case "CLOSE_WAIT":  return ANSI.fg(.red)
        default:            return ANSI.dim
        }
    }
}
