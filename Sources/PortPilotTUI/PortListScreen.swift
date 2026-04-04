// PortListScreen.swift — Main port list view for PortPilot TUI
//
// Displays all listening ports in a scrollable table with search, kill,
// and detail view navigation. This is the primary screen users interact with.

import Foundation
import TerminalTUI
import PortManagerLib

// MARK: - Shared Formatting

/// Alert state for TUI display
enum AlertState {
    case normal
    case warning
    case critical
    var isAlert: Bool { self != .normal }
}

/// Format memory in human-readable units (MB/GB) — shared across screens
func formatMemory(_ mb: Double) -> String {
    if mb >= 1024 { return String(format: "%.1fG", mb / 1024.0) }
    if mb >= 10   { return String(format: "%.0fM", mb) }
    return String(format: "%.1fM", mb)
}

// MARK: - Port List Screen

struct PortListScreen: TUIScreen {

    // MARK: - State

    private let portManager = PortManager()
    private var processes: [PortProcess] = []
    private var filtered: [PortProcess] = []
    private var selectedIndex: Int = 0
    private var scrollOffset: Int = 0

    // Search state
    private var isSearching: Bool = false
    private var searchQuery: String = ""
    private var searchBuffer: String = ""

    // Kill confirmation state
    private var confirmingKill: Bool = false

    // Status message (shown temporarily after actions)
    private var statusMessage: String?
    private var statusStyle: String = ANSI.fg(.green)

    // Tab state
    private var activeTab: Tab = .ports

    // Schedules tab state
    private var cronjobs: [CronjobEntry] = []
    private var filteredCronjobs: [CronjobEntry] = []

    // Connections tab state
    private var connections: [EstablishedConnection] = []
    private var filteredConnections: [EstablishedConnection] = []

    // Alert state
    private var alertState: AlertState = .normal

    // Cached visible row count for PageUp/PageDown
    private var cachedVisibleRows: Int = 15

    enum Tab: String, CaseIterable {
        case ports      = "Ports"
        case sockets    = "Sockets"
        case schedules  = "Schedules"
        case connections = "Connections"
    }

    // MARK: - Init

    init() {
        refresh()
    }

    // MARK: - Data

    /// Reload process list from the system
    private mutating func refresh() {
        do {
            switch activeTab {
            case .ports:
                processes = try portManager.getListeningProcesses()
                cronjobs = []
                filteredCronjobs = []
                connections = []
                filteredConnections = []
            case .sockets:
                processes = portManager.getUnixSocketProcesses()
                cronjobs = []
                filteredCronjobs = []
                connections = []
                filteredConnections = []
            case .schedules:
                cronjobs = portManager.getCronjobs()
                filteredCronjobs = cronjobs
                processes = []
                filtered = []
                connections = []
                filteredConnections = []
            case .connections:
                connections = try portManager.getAllConnections()
                filteredConnections = connections
                processes = []
                filtered = []
                cronjobs = []
                filteredCronjobs = []
                updateAlertState()
            }
            applyFilter()
            clampSelection()
            statusMessage = nil
        } catch {
            processes = []
            filtered = []
            cronjobs = []
            filteredCronjobs = []
            connections = []
            filteredConnections = []
            alertState = .normal
            showStatus("Error: \(error.localizedDescription)", style: ANSI.fg(.red))
        }
    }

    /// Update alert state based on current connections
    private mutating func updateAlertState() {
        let blocklistedCount = connections.filter { $0.isBlocklisted }.count
        let groupedConnections = Dictionary(grouping: connections, by: { $0.processName })
        let suspiciousCount = groupedConnections.filter { $0.value.count > 50 }.count

        if blocklistedCount > 0 {
            alertState = .critical
        } else if suspiciousCount > 0 {
            alertState = .warning
        } else {
            alertState = .normal
        }
    }

    /// Apply the current search filter
    private mutating func applyFilter() {
        if activeTab == .schedules {
            if searchQuery.isEmpty {
                filteredCronjobs = cronjobs
            } else {
                let query = searchQuery.lowercased()
                filteredCronjobs = cronjobs.filter { job in
                    job.command.lowercased().contains(query)
                        || (job.user ?? "").lowercased().contains(query)
                        || job.schedule.lowercased().contains(query)
                        || job.source.lowercased().contains(query)
                }
            }
        } else if activeTab == .connections {
            if searchQuery.isEmpty {
                filteredConnections = connections
            } else {
                let query = searchQuery.lowercased()
                filteredConnections = connections.filter { conn in
                    conn.remoteAddress.lowercased().contains(query)
                        || conn.processName.lowercased().contains(query)
                        || conn.user.lowercased().contains(query)
                        || "\(conn.pid)".contains(query)
                }
            }
        } else {
            if searchQuery.isEmpty {
                filtered = processes
            } else {
                let query = searchQuery.lowercased()
                filtered = processes.filter { proc in
                    proc.command.lowercased().contains(query)
                        || "\(proc.port)".contains(query)
                        || proc.user.lowercased().contains(query)
                        || "\(proc.pid)".contains(query)
                }
            }
        }
    }

    /// Keep selectedIndex within bounds
    private mutating func clampSelection() {
        let count: Int
        if activeTab == .schedules {
            count = filteredCronjobs.count
        } else if activeTab == .connections {
            count = filteredConnections.count
        } else {
            count = filtered.count
        }
        if count == 0 {
            selectedIndex = 0
        } else {
            selectedIndex = min(selectedIndex, count - 1)
        }
    }

    /// Set a temporary status message
    private mutating func showStatus(_ message: String, style: String = ANSI.fg(.green)) {
        statusMessage = message
        statusStyle = style
    }

    // MARK: - Rendering

    mutating func render(into screen: inout Screen) {
        let w = screen.width
        let h = screen.height
        guard h >= 4 else { return }  // Need minimum height for header + 1 row

        renderHeader(into: &screen, width: w)
        renderTable(into: &screen, width: w, height: h)
        renderStatusBar(into: &screen, width: w, height: h)
    }

    /// Render the app header with title and tabs
    private func renderHeader(into screen: inout Screen, width: Int) {
        let title = " PortPilot TUI "
        let platform = platformLabel()

        // Use red background for critical alert, orange for warning, blue for normal
        let headerStyle: String
        if alertState == .critical {
            headerStyle = ANSI.bold + ANSI.bg(.brightRed) + ANSI.fg(.white)
        } else if alertState == .warning {
            headerStyle = ANSI.bold + ANSI.bg(.brightYellow) + ANSI.fg(.black)
        } else {
            headerStyle = ANSI.bold + ANSI.bg(.blue) + ANSI.fg(.brightWhite)
        }

        // Alert indicator placement
        let alertText: String
        let alertWidth: Int
        if alertState.isAlert {
            alertText = alertState == .critical ? " ALERT " : " WARNING "
            alertWidth = alertText.count
        } else {
            alertText = ""
            alertWidth = 0
        }

        // Title row: reserve space for platform + alert at the end
        // platform + space = \(platform.count + 1), alert + space = \(alertWidth + 1) at end
        let reservedRight = (alertWidth > 0 ? alertWidth + 1 : 0) + platform.count + 1
        let titleAreaWidth = max(width - reservedRight, 20)
        let adjustedTitle = centerString(title, width: titleAreaWidth - 2)  // -2 for padding
        let titleRow = fitString(adjustedTitle + " " + platform + " ", width: width - reservedRight + 1)
        screen.put(row: 0, col: 0, text: titleRow, style: headerStyle)

        // Alert indicator at far right (after platform)
        if alertState.isAlert {
            let alertStyle = alertState == .critical
                ? ANSI.bold + ANSI.fg(.brightRed)
                : ANSI.bold + ANSI.fg(.brightYellow)
            screen.put(row: 0, col: width - alertWidth, text: alertText, style: alertStyle)
        }

        // Tab bar
        var col = 1
        for tab in Tab.allCases {
            let isActive = tab == activeTab
            let tabText = " \(tab.rawValue) "
            let style: String
            if isActive {
                style = ANSI.bold + ANSI.fg(.brightCyan) + ANSI.underline
            } else if alertState.isAlert && tab == .connections {
                // Highlight connections tab when there's an alert
                style = ANSI.bold + ANSI.fg(.brightRed)
            } else {
                style = ANSI.fg(.white)
            }
            screen.put(row: 1, col: col, text: tabText, style: style)
            col += tabText.count + 1
        }

        screen.horizontalLine(row: 2, col: 0, length: width, char: "─", style: ANSI.dim)
    }

    /// Render the port table
    private mutating func renderTable(into screen: inout Screen, width: Int, height: Int) {
        let tableOrigin = Point(row: 3, col: 0)
        let tableHeight = max(height - 5, 3)  // header(3) + statusbar(1) + msg(1)
        let tableSize = TerminalTUI.Size(width: width, height: tableHeight)

        let columns = tableColumns()

        // Adjust scroll offset to keep selection visible
        let visibleRows = max(tableHeight - 2, 1)
        cachedVisibleRows = visibleRows
        adjustScroll(visibleRows: visibleRows)

        if activeTab == .schedules {
            let table = Table(
                columns: columns,
                rowCount: filteredCronjobs.count,
                selectedRow: filteredCronjobs.isEmpty ? nil : selectedIndex,
                scrollOffset: scrollOffset,
                selectedStyle: ANSI.bg(.cyan) + ANSI.fg(.black),
                cellProvider: { [filteredCronjobs] row, col in
                    Self.cellContent(for: filteredCronjobs[row], column: col)
                }
            )
            table.render(into: &screen, at: tableOrigin, size: tableSize)

            if filteredCronjobs.isEmpty {
                let emptyMsg = searchQuery.isEmpty
                    ? "No cronjobs found."
                    : "No matches for \"\(searchQuery)\""
                screen.put(
                    row: tableOrigin.row + 3,
                    col: max(0, (width - emptyMsg.count) / 2),
                    text: emptyMsg,
                    style: ANSI.dim + ANSI.italic
                )
            }
        } else if activeTab == .connections {
            let table = Table(
                columns: columns,
                rowCount: filteredConnections.count,
                selectedRow: filteredConnections.isEmpty ? nil : selectedIndex,
                scrollOffset: scrollOffset,
                selectedStyle: ANSI.bg(.cyan) + ANSI.fg(.black),
                cellProvider: { [filteredConnections] row, col in
                    Self.cellContent(for: filteredConnections[row], column: col, isBlocklisted: filteredConnections[row].isBlocklisted)
                }
            )
            table.render(into: &screen, at: tableOrigin, size: tableSize)

            if filteredConnections.isEmpty {
                let emptyMsg = searchQuery.isEmpty
                    ? "No established connections."
                    : "No matches for \"\(searchQuery)\""
                screen.put(
                    row: tableOrigin.row + 3,
                    col: max(0, (width - emptyMsg.count) / 2),
                    text: emptyMsg,
                    style: ANSI.dim + ANSI.italic
                )
            }
        } else {
            let table = Table(
                columns: columns,
                rowCount: filtered.count,
                selectedRow: filtered.isEmpty ? nil : selectedIndex,
                scrollOffset: scrollOffset,
                selectedStyle: ANSI.bg(.cyan) + ANSI.fg(.black),
                cellProvider: { [filtered] row, col in
                    Self.cellContent(for: filtered[row], column: col)
                }
            )

            table.render(into: &screen, at: tableOrigin, size: tableSize)

            // Empty state
            if filtered.isEmpty {
                let emptyMsg = searchQuery.isEmpty
                    ? "No listening processes found."
                    : "No matches for \"\(searchQuery)\""
                screen.put(
                    row: tableOrigin.row + 3,
                    col: max(0, (width - emptyMsg.count) / 2),
                    text: emptyMsg,
                    style: ANSI.dim + ANSI.italic
                )
            }
        }
    }

    /// Render the bottom status bar and message line
    private func renderStatusBar(into screen: inout Screen, width: Int, height: Int) {
        guard height >= 3 else { return }
        let barRow = height - 2
        let msgRow = height - 1

        // Status bar with keybindings
        let items: [StatusBar.Item]
        if isSearching {
            items = [
                StatusBar.Item(key: "Enter", label: "Apply"),
                StatusBar.Item(key: "Esc", label: "Cancel"),
            ]
        } else if confirmingKill {
            items = [
                StatusBar.Item(key: "y", label: "Confirm Kill"),
                StatusBar.Item(key: "n/Esc", label: "Cancel"),
            ]
        } else if activeTab == .schedules {
            items = [
                StatusBar.Item(key: "↑↓/jk", label: "Navigate"),
                StatusBar.Item(key: "Enter", label: "Detail"),
                StatusBar.Item(key: "/", label: "Search"),
                StatusBar.Item(key: "Tab", label: "Switch Tab"),
                StatusBar.Item(key: "r", label: "Refresh"),
                StatusBar.Item(key: "q", label: "Quit"),
            ]
        } else if activeTab == .connections {
            items = [
                StatusBar.Item(key: "↑↓/jk", label: "Navigate"),
                StatusBar.Item(key: "Enter", label: "Detail"),
                StatusBar.Item(key: "/", label: "Search"),
                StatusBar.Item(key: "Tab", label: "Switch Tab"),
                StatusBar.Item(key: "r", label: "Refresh"),
                StatusBar.Item(key: "q", label: "Quit"),
            ]
        } else {
            items = [
                StatusBar.Item(key: "↑↓/jk", label: "Navigate"),
                StatusBar.Item(key: "Enter", label: "Kill"),
                StatusBar.Item(key: "/", label: "Search"),
                StatusBar.Item(key: "Tab", label: "Switch Tab"),
                StatusBar.Item(key: "i", label: "Info"),
                StatusBar.Item(key: "r", label: "Refresh"),
                StatusBar.Item(key: "q", label: "Quit"),
            ]
        }

        let bar = StatusBar(items: items)
        bar.render(into: &screen, at: Point(row: barRow, col: 0), size: TerminalTUI.Size(width: width, height: 1))

        // Message line (search prompt, kill confirmation, status, or filter info)
        if isSearching {
            let prompt = "Search: \(searchBuffer)_"
            screen.put(row: msgRow, col: 0, text: fitString(prompt, width: width), style: ANSI.bold + ANSI.fg(.yellow))
        } else if confirmingKill, activeTab != .connections, !filtered.isEmpty, selectedIndex < filtered.count {
            let proc = filtered[selectedIndex]
            let msg = "Kill \(proc.command) on port \(proc.port) (pid \(proc.pid))? [y/n]"
            screen.put(row: msgRow, col: 0, text: fitString(msg, width: width), style: ANSI.bold + ANSI.fg(.red))
        } else if let msg = statusMessage {
            screen.put(row: msgRow, col: 0, text: fitString(msg, width: width), style: statusStyle)
        } else if !searchQuery.isEmpty {
            let filterMsg = "Filter: \"\(searchQuery)\"  (/ to clear)"
            screen.put(row: msgRow, col: 0, text: fitString(filterMsg, width: width), style: ANSI.dim)
        } else if activeTab == .schedules {
            if !filteredCronjobs.isEmpty, selectedIndex < filteredCronjobs.count {
                let job = filteredCronjobs[selectedIndex]
                let countMsg = "\(filteredCronjobs.count) cronjob(s)"
                screen.put(row: msgRow, col: 0, text: fitString(countMsg, width: countMsg.count), style: ANSI.dim)
                let nextStr = job.nextRun.map { formatRelativeTime($0) } ?? "no next run"
                screen.put(row: msgRow, col: countMsg.count + 1, text: fitString("Next: \(nextStr)", width: width - countMsg.count - 1), style: ANSI.fg(.cyan))
            } else {
                let countMsg = "\(filteredCronjobs.count) cronjob(s) on \(platformLabel())"
                screen.put(row: msgRow, col: 0, text: fitString(countMsg, width: width), style: ANSI.dim)
            }
        } else if activeTab == .connections {
            if !filteredConnections.isEmpty, selectedIndex < filteredConnections.count {
                let conn = filteredConnections[selectedIndex]
                let isBlocklisted = conn.isBlocklisted
                let blocklistMarker = isBlocklisted ? "[!] BLOCKLISTED " : ""

                // Build count message with alert indicator
                let alertIndicator = alertState.isAlert ? " [!] " : " "
                let countMsg = "\(filteredConnections.count) connection(s)\(alertIndicator)"
                screen.put(row: msgRow, col: 0, text: fitString(countMsg, width: countMsg.count), style: ANSI.dim)

                let markerStyle = isBlocklisted ? ANSI.bold + ANSI.fg(.red) : ANSI.fg(.cyan)
                let suspiciousMarker = conn.remoteAddress.contains("*") ? "" : "→ \(conn.remoteAddress)"
                screen.put(row: msgRow, col: countMsg.count, text: fitString("\(blocklistMarker)\(conn.processName) \(suspiciousMarker)", width: width - countMsg.count), style: markerStyle)

                // Show alert summary if in alert state
                if alertState.isAlert {
                    let blocklistedCount = connections.filter { $0.isBlocklisted }.count
                    let groupedConnections = Dictionary(grouping: connections, by: { $0.processName })
                    let suspiciousProcesses = groupedConnections.filter { $0.value.count > 50 }

                    if blocklistedCount > 0 {
                        let alertMsg = " \(blocklistedCount) blocklisted"
                        let alertStyle = ANSI.bold + ANSI.fg(.brightRed)
                        screen.put(row: msgRow, col: width - alertMsg.count - 1, text: alertMsg, style: alertStyle)
                    } else if !suspiciousProcesses.isEmpty {
                        let topSuspicious = suspiciousProcesses.max { $0.value.count < $1.value.count }
                        if let (name, conns) = topSuspicious {
                            let alertMsg = " \(name):\(conns.count) [!]"
                            let alertStyle = ANSI.bold + ANSI.fg(.brightYellow)
                            screen.put(row: msgRow, col: max(0, width - alertMsg.count - 1), text: alertMsg, style: alertStyle)
                        }
                    }
                }
            } else {
                let countMsg = "\(filteredConnections.count) connection(s) on \(platformLabel())"
                screen.put(row: msgRow, col: 0, text: fitString(countMsg, width: width), style: ANSI.dim)
            }
        } else if !filtered.isEmpty, selectedIndex < filtered.count {
            // Show selected process's project root on the message line
            let proc = filtered[selectedIndex]
            let projectName = Self.projectLabel(for: proc)
            let prefix = "\(filtered.count) proc(s) "
            if projectName.isEmpty {
                screen.put(row: msgRow, col: 0, text: fitString("\(prefix)\(platformLabel())", width: width), style: ANSI.dim)
            } else {
                screen.put(row: msgRow, col: 0, text: fitString(prefix, width: prefix.count), style: ANSI.dim)
                screen.put(row: msgRow, col: prefix.count, text: fitString(projectName, width: width - prefix.count), style: ANSI.fg(.brightCyan))
            }
        } else {
            let countMsg = "\(filtered.count) process(es) on \(platformLabel())"
            screen.put(row: msgRow, col: 0, text: fitString(countMsg, width: width), style: ANSI.dim)
        }
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval < 0 { return "past" }
        if interval < 60 { return "in \(Int(interval))s" }
        if interval < 3600 { return "in \(Int(interval / 60))m" }
        if interval < 86400 { return "in \(Int(interval / 3600))h" }
        return "in \(Int(interval / 86400))d"
    }

    // MARK: - Key Handling

    mutating func handleKey(_ key: KeyEvent) -> ScreenAction {
        // Kill confirmation mode
        if confirmingKill {
            return handleConfirmKill(key)
        }

        // Search mode intercepts all keys
        if isSearching {
            return handleSearchKey(key)
        }

        switch key {
        case .char("q"), .char("Q"):
            return .quit

        case .arrow(.up), .char("k"):
            moveSelection(by: -1)

        case .arrow(.down), .char("j"):
            moveSelection(by: 1)

        case .pageUp:
            moveSelection(by: -max(cachedVisibleRows - 2, 5))

        case .pageDown:
            moveSelection(by: max(cachedVisibleRows - 2, 5))

        case .home:
            selectedIndex = 0

        case .end:
            if activeTab == .schedules {
                selectedIndex = max(0, filteredCronjobs.count - 1)
            } else if activeTab == .connections {
                selectedIndex = max(0, filteredConnections.count - 1)
            } else {
                selectedIndex = max(0, filtered.count - 1)
            }

        case .enter:
            if activeTab == .schedules {
                // Show cronjob detail
                if !filteredCronjobs.isEmpty, selectedIndex < filteredCronjobs.count {
                    return showCronjobDetail()
                }
            } else if activeTab == .connections {
                // Show connection detail
                if !filteredConnections.isEmpty, selectedIndex < filteredConnections.count {
                    return showConnectionDetail()
                }
            } else {
                // Enter starts kill confirmation — does NOT kill immediately
                if !filtered.isEmpty, selectedIndex < filtered.count {
                    confirmingKill = true
                }
            }

        case .char("/"):
            startSearch()

        case .char("i"), .char("I"):
            if activeTab == .schedules {
                if !filteredCronjobs.isEmpty, selectedIndex < filteredCronjobs.count {
                    return showCronjobDetail()
                }
            } else if activeTab == .connections {
                if !filteredConnections.isEmpty, selectedIndex < filteredConnections.count {
                    return showConnectionDetail()
                }
            } else {
                return showDetail()
            }

        case .tab:
            switchTab()

        case .char("r"), .char("R"), .ctrlR:
            refresh()
            showStatus("Refreshed", style: ANSI.fg(.green))

        case .ctrlC:
            return .quit

        default:
            break
        }

        return .continue
    }

    mutating func onResize(width: Int, height: Int) {
        clampSelection()
    }

    // MARK: - Navigation

    private mutating func moveSelection(by delta: Int) {
        let count: Int
        if activeTab == .schedules {
            count = filteredCronjobs.count
        } else if activeTab == .connections {
            count = filteredConnections.count
        } else {
            count = filtered.count
        }
        guard count > 0 else { return }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
    }

    private mutating func adjustScroll(visibleRows: Int) {
        guard visibleRows > 0 else { return }
        if selectedIndex < scrollOffset {
            scrollOffset = selectedIndex
        } else if selectedIndex >= scrollOffset + visibleRows {
            scrollOffset = selectedIndex - visibleRows + 1
        }
    }

    // MARK: - Search

    private mutating func startSearch() {
        if !searchQuery.isEmpty {
            // Clear existing search
            searchQuery = ""
            applyFilter()
            clampSelection()
        } else {
            isSearching = true
            searchBuffer = ""
        }
    }

    private mutating func handleSearchKey(_ key: KeyEvent) -> ScreenAction {
        switch key {
        case .enter:
            searchQuery = searchBuffer
            isSearching = false
            applyFilter()
            clampSelection()

        case .escape:
            isSearching = false
            searchBuffer = ""
            searchQuery = ""
            applyFilter()
            clampSelection()

        case .backspace:
            if !searchBuffer.isEmpty {
                searchBuffer.removeLast()
            }

        case .char(let ch):
            if searchBuffer.count < 64 {
                searchBuffer.append(ch)
            }

        case .ctrlC:
            isSearching = false
            searchBuffer = ""

        default:
            break
        }
        return .continue
    }

    // MARK: - Kill Confirmation

    private mutating func handleConfirmKill(_ key: KeyEvent) -> ScreenAction {
        switch key {
        case .char("y"), .char("Y"):
            confirmingKill = false
            killSelected()
        case .char("n"), .char("N"), .escape:
            confirmingKill = false
            showStatus("Kill cancelled", style: ANSI.dim)
        default:
            break  // Ignore other keys during confirmation
        }
        return .continue
    }

    private mutating func killSelected() {
        guard !filtered.isEmpty, selectedIndex < filtered.count else { return }
        let process = filtered[selectedIndex]

        do {
            if process.isUnixSocket {
                // Unix sockets have port=0; kill by PID directly
                try killByPID(process.pid, force: false)
            } else {
                try portManager.killProcessOnPort(process.port, force: false)
            }
            let label = process.isUnixSocket ? "pid \(process.pid)" : "port \(process.port)"
            showStatus("Killed \(process.command) on \(label)", style: ANSI.fg(.green))
            refresh()
        } catch {
            showStatus("Kill failed: \(error.localizedDescription)", style: ANSI.fg(.red))
        }
    }

    /// Kill a process by PID directly (used for unix socket processes)
    private func killByPID(_ pid: Int, force: Bool) throws {
        let signal = force ? "KILL" : "TERM"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/kill")
        process.arguments = ["-s", signal, "\(pid)"]
        try process.run()
        process.waitUntilExit()
    }

    // MARK: - Navigation Actions

    private mutating func showDetail() -> ScreenAction {
        guard !filtered.isEmpty, selectedIndex < filtered.count else { return .continue }
        let process = filtered[selectedIndex]
        let detailScreen = PortDetailScreen(process: process, portManager: portManager)
        return .push(detailScreen)
    }

    private mutating func showCronjobDetail() -> ScreenAction {
        guard !filteredCronjobs.isEmpty, selectedIndex < filteredCronjobs.count else { return .continue }
        let job = filteredCronjobs[selectedIndex]
        let detailScreen = CronjobDetailScreen(cronjob: job)
        return .push(detailScreen)
    }

    private mutating func showConnectionDetail() -> ScreenAction {
        guard !filteredConnections.isEmpty, selectedIndex < filteredConnections.count else { return .continue }
        let conn = filteredConnections[selectedIndex]
        let detailScreen = ConnectionDetailScreen(connection: conn)
        return .push(detailScreen)
    }

    private mutating func switchTab() {
        let allTabs = Tab.allCases
        if let idx = allTabs.firstIndex(of: activeTab) {
            activeTab = allTabs[(idx + 1) % allTabs.count]
        }
        selectedIndex = 0
        scrollOffset = 0
        confirmingKill = false  // Reset kill confirmation when switching tabs
        refresh()
    }

    // MARK: - Table Configuration

    /// Column definitions for the port table
    private func tableColumns() -> [TableColumn] {
        if activeTab == .sockets {
            return [
                TableColumn(title: "PID", width: 8),
                TableColumn(title: "USER", width: 12),
                TableColumn(title: "COMMAND", width: 16),
                TableColumn(title: "SOCKET PATH", width: 40),
            ]
        } else if activeTab == .schedules {
            return [
                TableColumn(title: "SCHEDULE", width: 22),
                TableColumn(title: "NEXT", width: 18),
                TableColumn(title: "USER", width: 12),
                TableColumn(title: "COMMAND", width: 25),
                TableColumn(title: "SOURCE", width: 20),
            ]
        } else if activeTab == .connections {
            return [
                TableColumn(title: "REMOTE", width: 30),
                TableColumn(title: "PROCESS", width: 16),
                TableColumn(title: "PID", width: 8),
                TableColumn(title: "USER", width: 12),
                TableColumn(title: "STATE", width: 12),
            ]
        }
        return [
            TableColumn(title: "PORT", width: 6),
            TableColumn(title: "PID", width: 10),
            TableColumn(title: "FRAMEWORK", width: 12),
            TableColumn(title: "PROJECT", width: 24),
            TableColumn(title: "UPTIME", width: 8),
            TableColumn(title: "STATUS", width: 8),
        ]
    }

    /// Provide cell content for a given process and column
    private static func cellContent(for process: PortProcess, column: Int) -> (text: String, style: String) {
        if process.isUnixSocket {
            // Sockets tab: PID, USER, COMMAND, SOCKET PATH
            switch column {
            case 0: return ("\(process.pid)", ANSI.fg(.brightMagenta))
            case 1: return (process.user, ANSI.fg(.brightBlue))
            case 2: return (process.command, ANSI.fg(.brightWhite))
            case 3: return (process.socketPath ?? "-", ANSI.dim)
            default: return ("", "")
            }
        }

        // Ports tab: PORT, PID, FRAMEWORK, PROJECT, UPTIME, STATUS
        switch column {
        case 0: return ("\(process.port)", ANSI.fg(.brightYellow))
        case 1: return ("\(process.pid)", ANSI.fg(.brightMagenta))
        case 2: return (process.framework ?? "-", process.framework.map { frameworkStyle($0) } ?? ANSI.dim)
        case 3: return (projectLabel(for: process), ANSI.fg(.cyan))
        case 4: return (uptimeString(for: process), ANSI.fg(.white))
        case 5: return (statusLabel(for: process), statusStyle(for: process))
        default: return ("", "")
        }
    }

    private static func frameworkStyle(_ framework: String) -> String {
        switch framework {
        case "Next.js", "Nuxt", "Remix", "Gatsby", "Astro":
            return ANSI.fg(.brightCyan)
        case "React", "Vue", "Angular", "Svelte":
            return ANSI.fg(.brightBlue)
        case "Node.js", "Express", "Fastify", "Koa":
            return ANSI.fg(.green)
        case "Python", "Django", "FastAPI":
            return ANSI.fg(.yellow)
        case "Rails", "Ruby":
            return ANSI.fg(.brightRed)
        case "Go", "Rust", "Java", ".NET", "PHP", "Laravel":
            return ANSI.fg(.brightMagenta)
        default:
            return ANSI.fg(.white)
        }
    }

    private static func uptimeString(for process: PortProcess) -> String {
        guard let startTime = process.startTime else { return "-" }
        let interval = Date().timeIntervalSince(startTime)
        guard interval >= 0 else { return "-" }

        let secondsInMinute: Double = 60
        let secondsInHour: Double = 3600
        let secondsInDay: Double = 86400

        let days = Int(interval / secondsInDay)
        let hours = Int((interval.truncatingRemainder(dividingBy: secondsInDay)) / secondsInHour)
        let minutes = Int((interval.truncatingRemainder(dividingBy: secondsInHour)) / secondsInMinute)

        if days > 0 {
            return "\(days)d\(hours)h"
        } else if hours > 0 {
            return "\(hours)h\(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }

    private static func statusLabel(for process: PortProcess) -> String {
        if process.isOrphaned { return "ORPHAN" }

        let cmd = process.command.lowercased()
        let dockerProcesses = ["docker", "containerd", "docker-proxy", "com.docker"]
        if dockerProcesses.contains(where: { cmd.contains($0) }) { return "DOCKER" }

        let devProcesses = ["node", "npm", "yarn", "python", "ruby", "rails", "go", "cargo", "java", "dotnet"]
        if devProcesses.contains(where: { cmd.contains($0) }) { return "DEV" }

        return "SYSTEM"
    }

    private static func statusStyle(for process: PortProcess) -> String {
        if process.isOrphaned { return ANSI.fg(.brightYellow) }

        let cmd = process.command.lowercased()
        let dockerProcesses = ["docker", "containerd", "docker-proxy", "com.docker"]
        if dockerProcesses.contains(where: { cmd.contains($0) }) { return ANSI.fg(.brightCyan) }

        let devProcesses = ["node", "npm", "yarn", "python", "ruby", "rails", "go", "cargo", "java", "dotnet"]
        if devProcesses.contains(where: { cmd.contains($0) }) { return ANSI.fg(.green) }

        return ANSI.fg(.white)
    }

    /// Provide cell content for a given cronjob and column
    private static func cellContent(for job: CronjobEntry, column: Int) -> (text: String, style: String) {
        switch column {
        case 0:
            let schedule = job.scheduleHuman ?? job.schedule
            return (truncated(schedule, to: 21), ANSI.fg(.brightYellow))
        case 1:
            if let nextRun = job.nextRun {
                let formatter = DateFormatter()
                formatter.dateFormat = "MM-dd HH:mm"
                return (formatter.string(from: nextRun), ANSI.fg(.cyan))
            }
            return ("-", ANSI.dim)
        case 2:
            return (job.user ?? "-", ANSI.fg(.brightBlue))
        case 3:
            return (truncated(job.command, to: 24), ANSI.fg(.brightWhite))
        case 4:
            let source = job.source == "user" ? "user" : shortSourcePath(job.source)
            return (source, ANSI.fg(.green))
        default:
            return ("", "")
        }
    }

    private static func shortSourcePath(_ path: String) -> String {
        if path == "user" { return "user" }
        let components = path.split(separator: "/").map(String.init)
        if components.count <= 3 { return path }
        return components.suffix(2).joined(separator: "/")
    }

    /// Provide cell content for a given connection and column
    private static func cellContent(for conn: EstablishedConnection, column: Int, isBlocklisted: Bool = false) -> (text: String, style: String) {
        switch column {
        case 0:
            let style = isBlocklisted ? ANSI.fg(.brightWhite) + ANSI.bold : ANSI.fg(.brightYellow)
            return (conn.remoteAddress, style)
        case 1:
            return (conn.processName, ANSI.fg(.brightWhite))
        case 2:
            return ("\(conn.pid)", ANSI.fg(.brightMagenta))
        case 3:
            return (conn.user, ANSI.fg(.brightBlue))
        case 4:
            let baseStyle = conn.state == "ESTABLISHED" ? ANSI.fg(.green) : ANSI.fg(.yellow)
            return (conn.state, isBlocklisted ? ANSI.fg(.brightWhite) : baseStyle)
        default:
            return ("", "")
        }
    }

    /// Build a short, useful source label: Docker container name, project dir, or category
    private static func sourceLabel(for process: PortProcess) -> String {
        let cmd = process.command.lowercased()

        // Check if this is a Docker/container process
        let dockerNames = ["docker", "dockerd", "containerd", "docker-proxy", "com.docker"]
        if dockerNames.contains(where: { cmd.contains($0) }) {
            // Try to get container name from the full command
            if let full = process.fullCommand, let name = extractDockerContainer(full) {
                return "[D] \(name)"
            }
            return "[D] docker"
        }

        // Check if process runs inside a container (Linux /proc/pid/cgroup)
        if let cgroup = try? String(contentsOfFile: "/proc/\(process.pid)/cgroup", encoding: .utf8),
           cgroup.contains("docker") || cgroup.contains("containerd") || cgroup.contains("/lxc/") {
            if let name = extractContainerID(cgroup) {
                return "[D] \(name)"
            }
            return "[D] container"
        }

        // Project directory
        let project = projectLabel(for: process)
        if !project.isEmpty { return project }

        // Fallback to category
        return categoryLabel(for: process.port)
    }

    /// Extract container name from docker-proxy command line
    /// e.g. "docker-proxy -proto tcp -host-ip 0.0.0.0 -host-port 5432 -container-ip 172.17.0.2 -container-port 5432"
    private static func extractDockerContainer(_ fullCommand: String) -> String? {
        // Look for known container-related flags
        let parts = fullCommand.split(separator: " ").map(String.init)
        // docker-proxy has -container-port but not a name; try to extract host-port
        if let portIdx = parts.firstIndex(of: "-host-port"), portIdx + 1 < parts.count {
            return "port:\(parts[portIdx + 1])"
        }
        return nil
    }

    /// Extract short container ID from /proc/pid/cgroup content
    private static func extractContainerID(_ cgroup: String) -> String? {
        // Lines like: 0::/docker/abc123def456...
        for line in cgroup.split(separator: "\n") {
            if let range = line.range(of: "docker/") {
                let id = String(line[range.upperBound...]).prefix(12)
                if !id.isEmpty { return String(id) }
            }
        }
        return nil
    }

    // MARK: - Formatting Helpers

    /// Truncate string to length with ellipsis
    private static func truncated(_ str: String, to length: Int) -> String {
        guard str.count > length, length >= 4 else { return str }
        return String(str.prefix(length - 3)) + "..."
    }

    /// Color CPU usage based on load (green < 10%, yellow < 50%, red >= 50%)
    private static func cpuStyle(_ cpu: Double?) -> String {
        guard let cpu else { return ANSI.dim }
        if cpu >= 50 { return ANSI.fg(.brightRed) }
        if cpu >= 10 { return ANSI.fg(.brightYellow) }
        return ANSI.fg(.green)
    }

    /// Human-readable port category
    private static func categoryLabel(for port: Int) -> String {
        switch port {
        case 80, 443, 8080, 8443, 3000, 3001, 5000, 5173, 4200, 9090: return "Web"
        case 3306, 5432, 27017, 6379, 9200, 5984, 8529, 1433, 1521:   return "DB"
        case 22:       return "SSH"
        case 53:       return "DNS"
        case 1...1023: return "Sys"
        default:       return "Dev"
        }
    }

    /// Style color per category
    private static func categoryStyle(for port: Int) -> String {
        switch categoryLabel(for: port) {
        case "Web": return ANSI.fg(.brightCyan)
        case "DB":  return ANSI.fg(.brightGreen)
        case "SSH": return ANSI.fg(.brightYellow)
        case "Sys": return ANSI.fg(.brightRed)
        default:    return ANSI.fg(.white)
        }
    }

    /// Extract a short project/origin label from a process's paths.
    /// e.g. "/mnt/c/sriinnu/personal/wooosh/client" → "wooosh/client"
    private static func projectLabel(for process: PortProcess) -> String {
        // Prefer working directory (where the process was launched from)
        if let cwd = process.workingDirectory, !cwd.isEmpty {
            return shortPath(cwd)
        }
        // Fall back to executable path
        if let path = process.processPath, !path.isEmpty {
            return shortPath(path)
        }
        // Fall back to full command (first arg is usually the binary path)
        if let full = process.fullCommand, !full.isEmpty {
            let firstArg = full.split(separator: " ").first.map(String.init) ?? full
            if firstArg.contains("/") { return shortPath(firstArg) }
            return firstArg
        }
        return ""
    }

    /// Shorten an absolute path to the last 2 meaningful components.
    /// Skips common prefixes like /mnt/c/Users, /home/user, /usr/lib, etc.
    private static func shortPath(_ path: String) -> String {
        let components = path.split(separator: "/").map(String.init)
        guard components.count >= 2 else { return path }

        // Skip system paths — show full short for them
        let systemPrefixes = ["usr", "bin", "sbin", "lib", "etc", "var", "System", "Library"]
        if let first = components.first, systemPrefixes.contains(first) {
            return components.suffix(2).joined(separator: "/")
        }

        // For user project paths, find the "interesting" part:
        // Skip mnt/c/Users/X, home/X, Users/X to get to the project
        var startIdx = 0
        for (i, comp) in components.enumerated() {
            if ["home", "mnt", "Users", "c"].contains(comp) { continue }
            // Skip the username component right after home/Users
            if i > 0, ["home", "Users"].contains(components[i - 1]) { continue }
            startIdx = i
            break
        }

        let meaningful = Array(components[startIdx...])
        if meaningful.count <= 3 {
            return meaningful.joined(separator: "/")
        }
        return meaningful.suffix(3).joined(separator: "/")
    }

    /// Current platform as a display label
    private func platformLabel() -> String {
        switch Platform.current {
        case .macOS:   return "macOS"
        case .linux:   return "Linux"
        case .wsl:     return "WSL"
        case .windows: return "Windows"
        }
    }
}
