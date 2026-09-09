import Foundation
import PortManagerLib
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

// MARK: - ANSI Escape Codes
enum ANSI {
    static let clear = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"
    static let dim = "\u{001B}[2m"
    static let underscore = "\u{001B}[4m"

    // Colors
    static let black = "\u{001B}[30m"
    static let red = "\u{001B}[31m"
    static let green = "\u{001B}[32m"
    static let yellow = "\u{001B}[33m"
    static let blue = "\u{001B}[34m"
    static let magenta = "\u{001B}[35m"
    static let cyan = "\u{001B}[36m"
    static let white = "\u{001B}[37m"

    // Background colors
    static let bgBlack = "\u{001B}[40m"
    static let bgRed = "\u{001B}[41m"
    static let bgGreen = "\u{001B}[42m"
    static let bgYellow = "\u{001B}[43m"
    static let bgBlue = "\u{001B}[44m"
    static let bgMagenta = "\u{001B}[45m"
    static let bgCyan = "\u{001B}[46m"
    static let bgWhite = "\u{001B}[47m"

    // Cursor positioning
    static func moveCursor(toLine line: Int) -> String {
        "\u{001B}[\(line);1H"
    }

    static func moveCursor(row: Int, col: Int) -> String {
        "\u{001B}[\(row);\(col)H"
    }

    static let hideCursor = "\u{001B}[?25l"
    static let showCursor = "\u{001B}[?25h"

    // Erase
    static let eraseLine = "\u{001B}[2K"
    static let eraseDown = "\u{001B}[0J"
    static let eraseScreen = "\u{001B}[2J"

    // Key codes
    static let arrowUp = "\u{001B}[A"
    static let arrowDown = "\u{001B}[B"
    static let arrowRight = "\u{001B}[C"
    static let arrowLeft = "\u{001B}[D"
    static let enter = "\r"
    static let escape = "\u{001B}"
    static let ctrlC = "\u{003}"
}

// MARK: - Port Info Display
struct PortInfoDisplay {
    let process: PortProcess
    let connections: [PortConnection]

    func render() -> String {
        var lines: [String] = []
        lines.append("")
        lines.append("\(ANSI.bold)\(ANSI.cyan)═\(String(repeating: "═", count: 60))\(ANSI.clear)")
        lines.append("\(ANSI.bold)\(ANSI.cyan)║\(ANSI.clear) Port Information \(ANSI.bold)\(ANSI.cyan)║\(ANSI.clear)")
        lines.append("\(ANSI.bold)\(ANSI.cyan)═\(String(repeating: "═", count: 60))\(ANSI.clear)")
        lines.append("")
        lines.append("  \(ANSI.bold)Port:\(ANSI.clear)      \(process.port)")
        lines.append("  \(ANSI.bold)Protocol:\(ANSI.clear)  \(process.protocolName.uppercased())")
        lines.append("  \(ANSI.bold)PID:\(ANSI.clear)       \(process.pid)")
        lines.append("  \(ANSI.bold)User:\(ANSI.clear)      \(process.user)")
        lines.append("  \(ANSI.bold)Command:\(ANSI.clear)   \(process.command)")
        if let fullCommand = process.fullCommand {
            lines.append("  \(ANSI.bold)Full Cmd:\(ANSI.clear) \(fullCommand)")
        }
        lines.append("")
        lines.append("\(ANSI.bold)\(ANSI.cyan)Connections:\(ANSI.clear)")

        if connections.isEmpty {
            lines.append("  No active connections")
        } else {
            for conn in connections {
                lines.append("  \(conn.localAddress) -> \(conn.remoteAddress) [\(conn.state)]")
            }
        }
        lines.append("")
        lines.append("\(ANSI.dim)Press any key to continue...\(ANSI.clear)")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Interactive Mode
final class InteractiveMode {
    private let portManager: PortManager
    private var processes: [PortProcess] = []
    private var filteredProcesses: [PortProcess] = []
    private var selectedIndex: Int = 0
    private var searchQuery: String = ""
    private var isSearching: Bool = false
    private var searchBuffer: String = ""
    private var isShowingInfo: Bool = false
    private var terminalLines: Int = 24
    /// Target captured when the kill prompt opened — a refresh between prompt
    /// and 'y' must not retarget the kill.
    private var pendingKill: PortProcess?

    /// Saved tty state, reachable from the signal handler (which can only
    /// touch globals).
    private static var savedTermios: termios?

    init(portManager: PortManager) {
        self.portManager = portManager
        setupTerminal()
    }

    deinit {
        cleanupTerminal()
    }

    private func setupTerminal() {
        // Get terminal size
        if let size = getTerminalSize() {
            terminalLines = size.lines
        }

        // Hide cursor, enter cbreak
        FileHandle.standardOutput.write(Data((ANSI.hideCursor + ANSI.eraseScreen).utf8))
        enterCbreakMode()
        installSignalHandlers()
    }

    private func cleanupTerminal() {
        restoreTerminal()
        FileHandle.standardOutput.write(Data((ANSI.showCursor + ANSI.eraseScreen).utf8))
    }

    private func getTerminalSize() -> (lines: Int, columns: Int)? {
        var size = winsize()
        guard ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size) == 0 else { return nil }
        return (Int(size.ws_row), Int(size.ws_col))
    }

    /// Cbreak mode: line editing off so keys arrive immediately, echo off.
    /// The old code only disabled ECHO — every keypress sat in the line
    /// discipline until Enter, then the whole buffered batch replayed at
    /// once, so buffered keys could navigate AND fire a kill unattended.
    private func enterCbreakMode() {
        var raw = termios()
        tcgetattr(STDIN_FILENO, &raw)
        Self.savedTermios = raw
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON)
        withUnsafeMutablePointer(to: &raw.c_cc) { ptr in
            let cc = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: cc_t.self)
            cc[Int(VMIN)] = 1
            cc[Int(VTIME)] = 0
        }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    }

    private func restoreTerminal() {
        guard var saved = Self.savedTermios else { return }
        Self.savedTermios = nil
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &saved)
    }

    /// Without these, Ctrl+C killed the process with the tty still in cbreak
    /// (echo off, no line editing) — the shell looked broken afterwards.
    /// Handler body is async-signal-safe: write, tcsetattr, _exit.
    private func installSignalHandlers() {
        let restoreAndExit: @convention(c) (Int32) -> Void = { signalNumber in
            var buf: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
                (0x1B, 0x5B, 0x3F, 0x32, 0x35, 0x68)  // \e[?25h — show cursor
            withUnsafePointer(to: &buf) { ptr in
                _ = write(STDOUT_FILENO, ptr, 6)
            }
            if var saved = InteractiveMode.savedTermios {
                tcsetattr(STDIN_FILENO, TCSAFLUSH, &saved)
            }
            _exit(128 &+ signalNumber)
        }
        signal(SIGINT, restoreAndExit)
        signal(SIGTERM, restoreAndExit)
    }

    func start(startPort: Int? = nil, endPort: Int? = nil) throws {
        refreshData(startPort: startPort, endPort: endPort)

        while true {
            if isShowingInfo {
                renderInfoScreen()
            } else {
                renderMainScreen()
            }

            // nil = EOF (Ctrl+D, closed pipe). The old empty-string return
            // spun this loop at 100% CPU forever.
            guard let key = readKey() else { return }

            if isShowingInfo {
                isShowingInfo = false
                continue
            }

            if pendingKill != nil {
                handleKillConfirmation(key, startPort: startPort, endPort: endPort)
                continue
            }

            switch key {
            case ANSI.arrowUp:
                navigateUp()
            case ANSI.arrowDown:
                navigateDown()
            case "/":
                startSearch()
            case "q", "Q":
                return
            case "r", "R":
                refreshData(startPort: startPort, endPort: endPort)
            case "i", "I":
                showPortInfo()
            case ANSI.enter, "\n":
                promptKillSelected()
            default:
                break
            }
        }
    }

    private func refreshData(startPort: Int?, endPort: Int?) {
        do {
            processes = try portManager.getListeningProcesses(startPort: startPort, endPort: endPort)
            applyFilter()
            selectedIndex = min(selectedIndex, max(0, filteredProcesses.count - 1))
        } catch {
            // Silently handle errors on refresh
        }
    }

    private func applyFilter() {
        if searchQuery.isEmpty {
            filteredProcesses = processes
        } else {
            filteredProcesses = processes.filter { process in
                process.command.lowercased().contains(searchQuery.lowercased()) ||
                "\(process.port)".contains(searchQuery) ||
                process.user.lowercased().contains(searchQuery.lowercased()) ||
                "\(process.pid)".contains(searchQuery)
            }
        }
    }

    private func navigateUp() {
        if filteredProcesses.isEmpty { return }
        selectedIndex = max(0, selectedIndex - 1)
    }

    private func navigateDown() {
        if filteredProcesses.isEmpty { return }
        selectedIndex = min(filteredProcesses.count - 1, selectedIndex + 1)
    }

    private func startSearch() {
        searchBuffer = ""
        isSearching = true

        while isSearching {
            renderSearchPrompt()

            guard let key = readKey() else {
                isSearching = false
                return
            }

            switch key {
            case ANSI.enter, "\n":
                searchQuery = searchBuffer
                applyFilter()
                selectedIndex = 0
                isSearching = false
            case ANSI.escape:
                isSearching = false
            case ANSI.ctrlC:
                isSearching = false
            case "\u{007F}", "\u{008}": // Backspace/Delete
                if !searchBuffer.isEmpty {
                    searchBuffer.removeLast()
                }
            default:
                if key.count == 1, let scalar = key.unicodeScalars.first, scalar.isASCII && scalar.value >= 32 && scalar.value < 127 {
                    searchBuffer.append(key)
                }
            }
        }
    }

    private func showPortInfo() {
        guard !filteredProcesses.isEmpty, selectedIndex < filteredProcesses.count else { return }
        // The main loop renders the info screen; any keypress dismisses it.
        // (The old version blocked on readKey() *before* the screen ever
        // rendered — the info screen was unreachable dead code.)
        isShowingInfo = true
    }

    /// Enter opens a y/n prompt instead of killing outright — one stray
    /// keypress shouldn't cost a process its life.
    private func promptKillSelected() {
        guard !filteredProcesses.isEmpty, selectedIndex < filteredProcesses.count else { return }
        pendingKill = filteredProcesses[selectedIndex]
    }

    private func handleKillConfirmation(_ key: String, startPort: Int?, endPort: Int?) {
        guard let target = pendingKill else { return }

        switch key {
        case "y", "Y", ANSI.enter, "\n":
            pendingKill = nil
            // PID-direct with TERM→KILL escalation: re-resolving by port
            // could hit whatever grabbed it since the last scan.
            let survivors = portManager.killProcess(pids: [target.pid])
            if survivors.isEmpty {
                renderKillConfirmation(process: target)
            } else {
                renderError("pid \(target.pid) survived SIGKILL")
            }
            refreshData(startPort: startPort, endPort: endPort)
        case "n", "N", ANSI.escape, "q", "Q":
            pendingKill = nil
        default:
            break
        }
    }

    private func renderKillConfirmation(process: PortProcess) {
        let message = "\(ANSI.green)Killed pid \(process.pid): \(process.command)\(ANSI.clear)"
        FileHandle.standardOutput.write(Data(message.utf8))
        sleep(1)
    }

    private func renderError(_ message: String) {
        let errorMsg = "\(ANSI.red)Error: \(message)\(ANSI.clear)"
        FileHandle.standardOutput.write(Data(errorMsg.utf8))
        sleep(1)
    }

    private func renderHeader() -> String {
        let title = " PortPilot - Interactive Port Manager "
        let width = getColumnWidth()

        return """
        \(ANSI.bgBlue)\(ANSI.white)\(ANSI.bold)
        ╔\(String(repeating: "═", count: width - 2))╗
        ║\(centerString(title, width: width - 2))║
        ╚\(String(repeating: "═", count: width - 2))╝
        \(ANSI.clear)
        """
    }

    private func renderTableHeader() -> String {
        let header = "  PORT    PROTO   PID      USER           COMMAND"
        return "\(ANSI.bold)\(ANSI.cyan)\(header)\(ANSI.clear)"
    }

    private func renderProcesses() -> String {
        guard !filteredProcesses.isEmpty else {
            return "\n  \(ANSI.dim)No processes found.\(ANSI.clear)"
        }

        var lines: [String] = []
        // max(1, …): a terminal shorter than the chrome made this negative,
        // and prefix() traps on a negative count.
        let maxVisible = max(1, terminalLines - 10)

        // Window the list around the selection so navigating past the first
        // screenful scrolls instead of marching the cursor off-screen.
        let scrollOffset = max(0, min(selectedIndex - maxVisible / 2, filteredProcesses.count - maxVisible))

        for (visibleIndex, process) in filteredProcesses.dropFirst(scrollOffset).prefix(maxVisible).enumerated() {
            let isSelected = (visibleIndex + scrollOffset) == selectedIndex
            lines.append(formatProcessRow(process, isSelected: isSelected))
        }

        if filteredProcesses.count > maxVisible {
            lines.append("\(ANSI.dim)… \(filteredProcesses.count - maxVisible) more (arrow keys scroll)\(ANSI.clear)")
        }

        return lines.joined(separator: "\n")
    }

    private func formatProcessRow(_ process: PortProcess, isSelected: Bool) -> String {
        let port = "\(process.port)".padding(toLength: 6, withPad: " ", startingAt: 0)
        let proto = process.protocolName.uppercased().padding(toLength: 6, withPad: " ", startingAt: 0)
        let pid = "\(process.pid)".padding(toLength: 8, withPad: " ", startingAt: 0)
        let user = process.user.padding(toLength: 14, withPad: " ", startingAt: 0)
        let command = process.command.prefix(30).padding(toLength: 30, withPad: " ", startingAt: 0)

        let row = "  \(port) \(proto) \(pid) \(user) \(command)"

        if isSelected {
            return "\(ANSI.bgCyan)\(ANSI.black)\(row)\(ANSI.clear)"
        } else {
            return row
        }
    }

    private func renderFooter() -> String {
        let count = filteredProcesses.count
        let total = processes.count

        let status = """
        \(ANSI.bold)Navigation:\(ANSI.clear) ↑↓ Navigate | \(ANSI.bold)Enter:\(ANSI.clear) Kill [y/n] | \(ANSI.bold)/:\(ANSI.clear) Search | \(ANSI.bold)i:\(ANSI.clear) Info | \(ANSI.bold)r:\(ANSI.clear) Refresh | \(ANSI.bold)q:\(ANSI.clear) Quit
        \(ANSI.dim)──────────────────────────────────────────────────────────────────────────────────────────────────────\(ANSI.clear)
        \(ANSI.bold)Ports:\(ANSI.clear) \(count) / \(total) shown
        """

        return status
    }

    private func renderSearchPrompt() {
        let prompt = "Search: \(searchBuffer)_"

        FileHandle.standardOutput.write(Data("\(ANSI.moveCursor(toLine: terminalLines - 3))".utf8))
        FileHandle.standardOutput.write(Data("\(ANSI.eraseLine)\(ANSI.bold)\(ANSI.yellow)\(prompt)\(ANSI.clear)".utf8))
    }

    private func renderMainScreen() {
        var output = ""
        output += ANSI.eraseScreen
        output += ANSI.moveCursor(toLine: 1)
        output += renderHeader()
        output += "\n"
        output += renderTableHeader()
        output += "\n"
        output += renderProcesses()
        output += "\n\n"
        output += renderFooter()

        if let target = pendingKill {
            output += "\n\(ANSI.bold)\(ANSI.red)Kill \(target.command) (pid \(target.pid))? [y/n]\(ANSI.clear)"
        } else if !searchQuery.isEmpty {
            output += "\n\(ANSI.dim)Filter: \"\(searchQuery)\" (press / to clear)\(ANSI.clear)"
        }

        FileHandle.standardOutput.write(Data(output.utf8))
    }

    private func renderInfoScreen() {
        guard !filteredProcesses.isEmpty else { return }
        let process = filteredProcesses[selectedIndex]

        do {
            let connections = try portManager.getConnections(for: process.port)
            let info = PortInfoDisplay(process: process, connections: connections)

            var output = ""
            output += ANSI.eraseScreen
            output += ANSI.moveCursor(toLine: 1)
            output += info.render()

            FileHandle.standardOutput.write(Data(output.utf8))
        } catch {
            isShowingInfo = false
        }
    }

    private func getColumnWidth() -> Int {
        if let size = getTerminalSize() {
            return min(size.columns, 100)
        }
        return 80
    }

    private func centerString(_ string: String, width: Int) -> String {
        let padding = max(0, (width - string.count) / 2)
        return String(repeating: " ", count: padding) + string
    }

    /// Read one key. Returns nil on EOF (Ctrl+D, closed pipe).
    private func readKey() -> String? {
        var buf = [UInt8](repeating: 0, count: 1)

        guard read(STDIN_FILENO, &buf, 1) == 1 else { return nil }

        // Escape sequences — tail bytes are polled with a short timeout so a
        // bare Escape press doesn't block waiting for a byte that never comes.
        if buf[0] == 0x1B {
            guard let second = peekByte() else { return ANSI.escape }

            guard second == 0x5B else { return ANSI.escape }  // '['
            // Swallow numeric parameter bytes (ESC[5~, ESC[1;5A, …) so the
            // terminating letter really terminates — otherwise the '~' leaks
            // through as a phantom keypress.
            var final: UInt8
            while true {
                guard let byte = peekByte() else { return "" }
                if (0x30...0x3F).contains(byte) { continue }
                final = byte
                break
            }

            switch final {
            case 0x41: return ANSI.arrowUp
            case 0x42: return ANSI.arrowDown
            case 0x43: return ANSI.arrowRight
            case 0x44: return ANSI.arrowLeft
            default: return ""
            }
        }

        return String(bytes: [buf[0]], encoding: .utf8) ?? ""
    }

    /// Read one byte if it arrives within ~50ms — for escape-sequence tails.
    private func peekByte() -> UInt8? {
        var pollFd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        guard poll(&pollFd, 1, 50) > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: 1)
        guard read(STDIN_FILENO, &buf, 1) == 1 else { return nil }
        return buf[0]
    }
}
