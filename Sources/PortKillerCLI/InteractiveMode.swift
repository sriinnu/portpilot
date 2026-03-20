import Foundation
import PortManagerLib

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

        // Hide cursor, disable echo
        FileHandle.standardOutput.write(Data((ANSI.hideCursor + ANSI.eraseScreen).utf8))
        disableEcho()
    }

    private func cleanupTerminal() {
        enableEcho()
        FileHandle.standardOutput.write(Data((ANSI.showCursor + ANSI.eraseScreen).utf8))
    }

    private func getTerminalSize() -> (lines: Int, columns: Int)? {
        var size = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0 else { return nil }
        return (Int(size.ws_row), Int(size.ws_col))
    }

    private func disableEcho() {
        var flags = termios()
        tcgetattr(STDIN_FILENO, &flags)
        flags.c_lflag &= ~UInt(ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &flags)
    }

    private func enableEcho() {
        var flags = termios()
        tcgetattr(STDIN_FILENO, &flags)
        flags.c_lflag |= UInt(ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &flags)
    }

    func start(startPort: Int? = nil, endPort: Int? = nil) throws {
        refreshData(startPort: startPort, endPort: endPort)

        while true {
            if isShowingInfo {
                renderInfoScreen()
            } else {
                renderMainScreen()
            }

            let key = readKey()

            if isShowingInfo {
                isShowingInfo = false
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
                killSelectedPort(startPort: startPort, endPort: endPort)
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

            let key = readKey()

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
        guard !filteredProcesses.isEmpty else { return }
        let process = filteredProcesses[selectedIndex]

        do {
            _ = try portManager.getConnections(for: process.port)
            isShowingInfo = true

            // Wait for key press then return
            _ = readKey()
            isShowingInfo = false
        } catch {
            // Silently fail
        }
    }

    private func killSelectedPort(startPort: Int?, endPort: Int?) {
        guard !filteredProcesses.isEmpty else { return }
        let process = filteredProcesses[selectedIndex]

        do {
            try portManager.killProcessOnPort(process.port, force: false)
            renderKillConfirmation(process: process)
            refreshData(startPort: startPort, endPort: endPort)
        } catch {
            renderError(error.localizedDescription)
        }
    }

    private func renderKillConfirmation(process: PortProcess) {
        let message = "\(ANSI.green)Killed process on port \(process.port): \(process.command)\(ANSI.clear)"
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
        let maxVisible = terminalLines - 10 // Leave room for header, footer, and status bar

        for (index, process) in filteredProcesses.prefix(maxVisible).enumerated() {
            let isSelected = index == selectedIndex
            let line = formatProcessRow(process, isSelected: isSelected)
            lines.append(line)
        }

        if filteredProcesses.count > maxVisible {
            lines.append("\(ANSI.dim)... and \(filteredProcesses.count - maxVisible) more (scroll with arrow keys)\(ANSI.clear)")
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
        \(ANSI.bold)Navigation:\(ANSI.clear) ↑↓ Navigate | \(ANSI.bold)Enter:\(ANSI.clear) Kill | \(ANSI.bold)/:\(ANSI.clear) Search | \(ANSI.bold)i:\(ANSI.clear) Info | \(ANSI.bold)r:\(ANSI.clear) Refresh | \(ANSI.bold)q:\(ANSI.clear) Quit
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

        if !searchQuery.isEmpty {
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

    private func readKey() -> String {
        let fd = STDIN_FILENO
        var buf = [UInt8](repeating: 0, count: 1)

        // Read first byte
        guard read(fd, &buf, 1) == 1 else { return "" }

        // Handle escape sequences
        if buf[0] == 0x1B { // ESC
            // Peek at next byte
            var peekBuf = [UInt8](repeating: 0, count: 1)
            if read(fd, &peekBuf, 1) == 1 {
                if peekBuf[0] == 0x5B { // [
                    // Get the final byte
                    if read(fd, &peekBuf, 1) == 1 {
                        switch peekBuf[0] {
                        case 0x41: return ANSI.arrowUp    // Up
                        case 0x42: return ANSI.arrowDown  // Down
                        case 0x43: return ANSI.arrowRight // Right
                        case 0x44: return ANSI.arrowLeft  // Left
                        default: return ""
                        }
                    }
                }
            }
            return ANSI.escape
        }

        return String(bytes: [buf[0]], encoding: .utf8) ?? ""
    }
}
