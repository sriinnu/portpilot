// ProcessTreeView.swift — Hierarchical process tree visualization
//
// Shows parent/child relationships between processes with tree lines
// and indentation.

import Foundation
import TerminalTUI
import PortManagerLib

// MARK: - Process Tree Node

struct ProcessTreeNode {
    var process: PortProcess
    var children: [ProcessTreeNode]
    var depth: Int
    var isExpanded: Bool

    init(process: PortProcess, depth: Int = 0) {
        self.process = process
        self.children = []
        self.depth = depth
        self.isExpanded = false
    }

    mutating func addChild(_ child: ProcessTreeNode) {
        children.append(child)
    }
}

// MARK: - Process Tree View

struct ProcessTreeView: TUIScreen {
    var rootNode: ProcessTreeNode?
    private var flattenedNodes: [ProcessTreeNode] = []
    private var selectedIndex: Int = 0
    private var scrollOffset: Int = 0
    private var searchQuery: String = ""
    private var isSearching: Bool = false
    private var searchBuffer: String = ""

    private let portManager = PortManager()
    private var allProcesses: [PortProcess] = []

    init() {
        refresh()
    }

    mutating func refresh() {
        do {
            allProcesses = try portManager.getListeningProcesses()
            buildTree()
            flattenTree()
        } catch {
            allProcesses = []
            rootNode = nil
            flattenedNodes = []
        }
    }

    private mutating func buildTree() {
        // Group processes by parent PID
        var byPPID: [Int: [PortProcess]] = [:]
        var rootProcesses: [PortProcess] = []

        for proc in allProcesses {
            if let ppid = proc.parentPID {
                if byPPID[ppid] == nil {
                    byPPID[ppid] = []
                }
                byPPID[ppid]?.append(proc)
            } else {
                rootProcesses.append(proc)
            }
        }

        // Build tree recursively
        if let firstRoot = rootProcesses.first {
            rootNode = buildNode(firstRoot, byPPID: byPPID, depth: 0)
        }
    }

    private func buildNode(_ process: PortProcess, byPPID: [Int: [PortProcess]], depth: Int) -> ProcessTreeNode {
        var node = ProcessTreeNode(process: process, depth: depth)

        if let children = byPPID[process.pid] {
            for child in children {
                let childNode = buildNode(child, byPPID: byPPID, depth: depth + 1)
                node.addChild(childNode)
            }
        }

        return node
    }

    private mutating func flattenTree() {
        flattenedNodes = []
        if let root = rootNode {
            flattenNode(root)
        }
    }

    private mutating func flattenNode(_ node: ProcessTreeNode) {
        flattenedNodes.append(node)
        if node.isExpanded {
            for child in node.children {
                flattenNode(child)
            }
        }
    }

    // MARK: - Rendering

    mutating func render(into screen: inout Screen) {
        let w = screen.width
        let h = screen.height
        guard h >= 4 else { return }

        renderHeader(into: &screen, width: w)
        renderTree(into: &screen, width: w, height: h)
        renderStatusBar(into: &screen, width: w, height: h)
    }

    private func renderHeader(into screen: inout Screen, width: Int) {
        let theme = TUIThemeManager.shared
        let colors = theme.colors

        // Header with tree icon
        let title = " Process Tree "
        screen.put(row: 0, col: 0, text: title, style: theme.fonts.titleStyle + ANSI.bg(colors.primary))
        screen.horizontalLine(row: 1, col: 0, length: width, char: "─", style: ANSI.dim)

        // Column headers
        screen.put(row: 2, col: 2, text: "TREE", style: theme.fonts.headerStyle)
        let colOffset = width - 45
        screen.put(row: 2, col: colOffset, text: "PID", style: theme.fonts.headerStyle)
        screen.put(row: 2, col: colOffset + 8, text: "PORT", style: theme.fonts.headerStyle)
        screen.put(row: 2, col: colOffset + 16, text: "CPU", style: theme.fonts.headerStyle)
        screen.put(row: 2, col: colOffset + 24, text: "MEM", style: theme.fonts.headerStyle)

        screen.horizontalLine(row: 3, col: 0, length: width, char: "─", style: ANSI.dim)
    }

    private mutating func renderTree(into screen: inout Screen, width: Int, height: Int) {
        let theme = TUIThemeManager.shared
        let colors = theme.colors
        let tableOrigin = Point(row: 4, col: 0)
        let tableHeight = max(height - 6, 3)
        let visibleRows = tableHeight

        // Adjust scroll
        adjustScroll(visibleRows: visibleRows)

        for i in 0..<min(visibleRows, flattenedNodes.count) {
            let nodeIndex = scrollOffset + i
            guard nodeIndex < flattenedNodes.count else { break }

            let node = flattenedNodes[nodeIndex]
            let isSelected = nodeIndex == selectedIndex
            let row = tableOrigin.row + i

            // Selection highlight
            if isSelected {
                screen.put(row: row, col: 0, text: String(repeating: " ", count: width), style: ANSI.bg(colors.highlight))
            }

            // Tree lines and indentation
            let indent = String(repeating: "  ", count: node.depth)
            let treePrefix: String
            if node.children.isEmpty {
                treePrefix = indent + "╰─ "
            } else if node.isExpanded {
                treePrefix = indent + "▼─ "
            } else {
                treePrefix = indent + "▶─ "
            }

            let processName = fitString(node.process.command, width: width - 50 - node.depth * 2)
            let style = isSelected ? theme.fonts.bodyStyle + ANSI.bg(colors.highlight) : theme.fonts.bodyStyle

            screen.put(row: row, col: 2, text: treePrefix, style: ANSI.fg(colors.accent))
            screen.put(row: row, col: 2 + treePrefix.count, text: processName, style: style)

            // PID, PORT, CPU, MEM
            let colOffset = width - 45
            screen.put(row: row, col: colOffset, text: "\(node.process.pid)", style: isSelected ? style : ANSI.fg(colors.textMuted))
            screen.put(row: row, col: colOffset + 8, text: "\(node.process.port)", style: isSelected ? style : ANSI.fg(colors.accent))

            let cpuVal = node.process.cpuUsage ?? 0
            let cpuStyle = cpuVal > 80 ? colors.error : (cpuVal > 50 ? colors.warning : colors.success)
            screen.put(row: row, col: colOffset + 16, text: String(format: "%4.1f", cpuVal), style: isSelected ? style : ANSI.fg(cpuStyle))

            let memVal = node.process.memoryMB ?? 0
            let memStyle = memVal > 100 ? colors.error : (memVal > 50 ? colors.warning : colors.accent)
            screen.put(row: row, col: colOffset + 24, text: formatMemory(memVal), style: isSelected ? style : ANSI.fg(memStyle))
        }

        // Empty state
        if flattenedNodes.isEmpty {
            let msg = "No processes to display"
            screen.put(row: tableOrigin.row + 2, col: max(0, (width - msg.count) / 2), text: msg, style: ANSI.dim + ANSI.italic)
        }
    }

    private func renderStatusBar(into screen: inout Screen, width: Int, height: Int) {
        guard height >= 2 else { return }
        let barRow = height - 2
        let msgRow = height - 1

        let theme = TUIThemeManager.shared

        // Keybindings
        let items: [StatusBar.Item]
        if isSearching {
            items = [
                StatusBar.Item(key: "Enter", label: "Apply"),
                StatusBar.Item(key: "Esc", label: "Cancel"),
            ]
        } else {
            items = [
                StatusBar.Item(key: "↑↓", label: "Navigate"),
                StatusBar.Item(key: "Enter/Space", label: "Expand"),
                StatusBar.Item(key: "/", label: "Search"),
                StatusBar.Item(key: "r", label: "Refresh"),
                StatusBar.Item(key: "q", label: "Quit"),
            ]
        }

        let bar = StatusBar(items: items)
        bar.render(into: &screen, at: Point(row: barRow, col: 0), size: TerminalTUI.Size(width: width, height: 1))

        // Message line
        if isSearching {
            let prompt = "Search: \(searchBuffer)_"
            screen.put(row: msgRow, col: 0, text: fitString(prompt, width: width), style: ANSI.bold + ANSI.fg(theme.colors.accent))
        } else if !searchQuery.isEmpty {
            screen.put(row: msgRow, col: 0, text: "Filter: \"\(searchQuery)\"  (/ to clear)", style: ANSI.dim)
        } else {
            let count = "\(flattenedNodes.count) processes"
            screen.put(row: msgRow, col: 0, text: count, style: ANSI.dim)
        }
    }

    // MARK: - Key Handling

    mutating func handleKey(_ key: KeyEvent) -> ScreenAction {
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

        case .enter, .char(" "):
            toggleExpansion()

        case .char("/"):
            if searchQuery.isEmpty {
                isSearching = true
                searchBuffer = ""
            } else {
                searchQuery = ""
                flattenTree()
            }

        case .char("r"), .char("R"):
            refresh()

        case .ctrlC:
            return .quit

        default:
            break
        }

        return .continue
    }

    private mutating func handleSearchKey(_ key: KeyEvent) -> ScreenAction {
        switch key {
        case .enter:
            searchQuery = searchBuffer
            isSearching = false
            applyFilter()

        case .escape:
            isSearching = false
            searchBuffer = ""

        case .backspace:
            if !searchBuffer.isEmpty {
                searchBuffer.removeLast()
            }

        case .char(let ch):
            if searchBuffer.count < 64 {
                searchBuffer.append(ch)
            }

        default:
            break
        }
        return .continue
    }

    private mutating func applyFilter() {
        // Rebuild tree with filtered processes
        let filtered = searchQuery.isEmpty ? allProcesses : allProcesses.filter { proc in
            proc.command.lowercased().contains(searchQuery.lowercased())
                || "\(proc.pid)".contains(searchQuery)
                || "\(proc.port)".contains(searchQuery)
        }

        allProcesses = filtered
        buildTree()
        flattenTree()
        selectedIndex = 0
        scrollOffset = 0
    }

    // MARK: - Navigation

    private mutating func moveSelection(by delta: Int) {
        guard !flattenedNodes.isEmpty else { return }
        selectedIndex = max(0, min(flattenedNodes.count - 1, selectedIndex + delta))
    }

    private mutating func adjustScroll(visibleRows: Int) {
        guard visibleRows > 0 else { return }
        if selectedIndex < scrollOffset {
            scrollOffset = selectedIndex
        } else if selectedIndex >= scrollOffset + visibleRows {
            scrollOffset = selectedIndex - visibleRows + 1
        }
    }

    private mutating func toggleExpansion() {
        guard selectedIndex < flattenedNodes.count else { return }
        flattenedNodes[selectedIndex].isExpanded.toggle()
        flattenTree()
    }

    mutating func onResize(width: Int, height: Int) {
        // Recalculate scroll offset
        let visibleRows = max(height - 6, 3)
        adjustScroll(visibleRows: visibleRows)
    }
}
