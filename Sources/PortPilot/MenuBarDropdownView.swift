import SwiftUI

private let menuBarSelectionSpring = Animation.spring(response: 0.26, dampingFraction: 0.84, blendDuration: 0.1)

// MARK: - Protocol Filter for Menu Bar
enum MenuBarProtocolFilter: String, CaseIterable {
    case all = "All"
    case tcp = "TCP"
    case udp = "UDP"
}

// MARK: - Menu Bar Dropdown View
struct MenuBarDropdownView: View {
    @ObservedObject var viewModel: PortViewModel
    @ObservedObject private var appSettings = AppSettings.shared
    let onOpenMainWindow: () -> Void
    let onQuit: () -> Void
    let onDismiss: () -> Void
    let onOpenSettings: () -> Void
    let onSponsors: () -> Void

    @State private var searchText = ""
    @State private var protocolFilter: MenuBarProtocolFilter = .all
    @State private var showTreeView = false
    @State private var hideSystemProcesses = false
    @State private var sourceFilter: PortSourceFilter = .all
    @State private var connectionTypeFilter: ConnectionType? = nil
    @State private var activeTab: MenuBarTab = .ports

    enum MenuBarTab: String, CaseIterable {
        case ports = "Ports"
        case sockets = "Sockets"
    }

    private var searchablePorts: [PortProcess] {
        var result = viewModel.ports

        if hideSystemProcesses {
            result = result.filter { !ProcessClassifier.shared.isSystemProcess(pid: $0.pid) }
        }

        if protocolFilter != .all {
            result = result.filter {
                $0.protocolName.lowercased() == protocolFilter.rawValue.lowercased()
            }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.command.lowercased().contains(query) ||
                String($0.port).contains(query) ||
                String($0.pid).contains(query)
            }
        }

        return result
    }

    private var filteredPorts: [PortProcess] {
        var result = searchablePorts

        if sourceFilter != .all {
            result = result.filter { viewModel.matchesSourceFilter(sourceFilter, for: $0) }
        }

        if let typeFilter = connectionTypeFilter {
            result = result.filter { viewModel.connectionType(for: $0) == typeFilter }
        }

        return result
    }

    private var networkPorts: [PortProcess] {
        filteredPorts.filter { !$0.isUnixSocket }
    }

    private var socketProcesses: [PortProcess] {
        filteredPorts.filter { $0.isUnixSocket }
    }

    private var groupedPorts: [(process: String, ports: [PortProcess])] {
        let dict = Dictionary(grouping: filteredPorts, by: { $0.command })
        return dict.sorted { $0.key < $1.key }.map { (process: $0.key, ports: $0.value) }
    }

    private var groupedFilteredPorts: [ConnectionType: [PortProcess]] {
        Dictionary(grouping: filteredPorts) { viewModel.connectionType(for: $0) }
    }

    private var sourceCounts: [PortSourceFilter: Int] {
        [
            .all: searchablePorts.count,
            .database: searchablePorts.filter { viewModel.matchesSourceFilter(.database, for: $0) }.count,
            .orbstack: searchablePorts.filter { viewModel.matchesSourceFilter(.orbstack, for: $0) }.count,
            .tunnels: searchablePorts.filter { viewModel.matchesSourceFilter(.tunnels, for: $0) }.count
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar + count badge
            MenuBarSearchHeader(
                searchText: $searchText
            )

            // Tab switcher: Ports | Sockets
            HStack(spacing: 4) {
                ForEach(MenuBarTab.allCases, id: \.self) { tab in
                    let count = tab == .ports ? networkPorts.count : socketProcesses.count
                    Button(action: {
                        withAnimation(menuBarSelectionSpring) {
                            activeTab = tab
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: tab == .ports ? Theme.Icon.portsTab : Theme.Icon.socketsTab)
                                .font(.system(size: 12, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                            Text("\(count)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(activeTab == tab ? .white.opacity(0.7) : .secondary.opacity(0.6))
                        }
                        .foregroundColor(activeTab == tab ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            activeTab == tab
                                ? Theme.Badge.accentBackground
                                : Color.clear
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    activeTab == tab ? Color.white.opacity(0.14) : Color.clear,
                                    lineWidth: 1
                                )
                        )
                        .cornerRadius(10)
                        .animation(menuBarSelectionSpring, value: activeTab)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.Surface.headerTint)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // Filter pills (only for Ports tab)
            if activeTab == .ports {
                MenuBarFilterBar(
                    protocolFilter: $protocolFilter,
                    sourceFilter: $sourceFilter,
                    connectionTypeFilter: $connectionTypeFilter,
                    hideSystemProcesses: $hideSystemProcesses,
                    sourceCounts: sourceCounts,
                    typeCounts: groupedFilteredPorts.mapValues { $0.count }
                )
            }

            Divider()
                .padding(.top, 5)
                .padding(.bottom, 7)

            // Content based on tab
            Group {
                if activeTab == .ports {
                    // Port sections
                    if networkPorts.isEmpty {
                        MenuBarEmptyState(
                            hasSearch: !searchText.isEmpty
                                || protocolFilter != .all
                                || sourceFilter != .all
                                || connectionTypeFilter != nil
                                || hideSystemProcesses
                        )
                    } else if showTreeView {
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(groupedPorts.filter { $0.ports.contains(where: { !$0.isUnixSocket }) }, id: \.process) { group in
                                    let netPorts = group.ports.filter { !$0.isUnixSocket }
                                    if !netPorts.isEmpty {
                                        MenuBarTreeSection(
                                            processName: group.process,
                                            ports: netPorts,
                                            onKill: { port in viewModel.killPort(port) },
                                            onCopy: { port in viewModel.copyPortInfo(port) }
                                        )
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    } else {
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(ConnectionType.allCases) { type in
                                    let portsForType = (groupedFilteredPorts[type] ?? []).filter { !$0.isUnixSocket }
                                    if !portsForType.isEmpty {
                                        MenuBarPortSection(
                                            title: type.rawValue,
                                            icon: type.icon,
                                            iconColor: type.color,
                                            ports: portsForType,
                                            onKill: { port in viewModel.killPort(port) },
                                            onCopy: { port in viewModel.copyPortInfo(port) },
                                            tunnelDetailProvider: { port in viewModel.tunnelDetail(for: port) },
                                            tunnelNameProvider: { port in viewModel.tunnelName(for: port) },
                                            namespaceProvider: type == .kubernetes ? { port in viewModel.kubeNamespace(for: port) } : nil,
                                            isLocalSection: type == .local,
                                            statusColor: type.color
                                        )
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                } else {
                    // Sockets tab - show Unix socket processes with PIDs
                    if socketProcesses.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: Theme.Icon.socketsTab)
                                .font(.system(size: 24))
                                .foregroundColor(.secondary)
                            Text("No App Sockets")
                                .font(.system(size: 13, weight: .medium))
                            Text("Local app daemons with Unix sockets appear here")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(socketProcesses, id: \.id) { proc in
                                    MenuBarSocketRow(
                                        process: proc,
                                        processType: ProcessClassifier.shared.classify(pid: proc.pid),
                                        onKill: { viewModel.killPort(proc.port) },
                                        onCopy: { viewModel.copyPortInfo(proc) }
                                    )
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 280)

            VStack(spacing: 10) {
                // I keep command-style actions grouped so the bottom of the popover reads as one system.
                MenuBarQuickActions(
                    onRefresh: { viewModel.refreshPorts() },
                    onToggleTreeView: { showTreeView.toggle() },
                    isTreeView: showTreeView,
                    onKillAll: {
                        let allPorts = Set(viewModel.ports)
                        viewModel.killSelectedPorts(allPorts)
                    },
                    hasActivePorts: !viewModel.ports.isEmpty
                )

                MenuBarBottomActions(
                    onOpenMainWindow: {
                        onDismiss()
                        onOpenMainWindow()
                    },
                    onSettings: {
                        onDismiss()
                        onOpenSettings()
                    },
                    onQuit: onQuit
                )

                MenuBarFooterLink(
                    label: "Sponsor PortPilot",
                    icon: Theme.Icon.sponsors,
                    action: {
                        onDismiss()
                        onSponsors()
                    }
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .frame(width: 320)
    }
}

// MARK: - Filter Bar
struct MenuBarFilterBar: View {
    @Binding var protocolFilter: MenuBarProtocolFilter
    @Binding var sourceFilter: PortSourceFilter
    @Binding var connectionTypeFilter: ConnectionType?
    @Binding var hideSystemProcesses: Bool
    let sourceCounts: [PortSourceFilter: Int]
    let typeCounts: [ConnectionType: Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PortSourceFilter.allCases) { source in
                        MenuBarSourceFilterChip(
                            label: source.rawValue,
                            count: sourceCounts[source] ?? 0,
                            icon: source.icon,
                            tint: source.color,
                            isSelected: sourceFilter == source,
                            action: {
                                withAnimation(menuBarSelectionSpring) {
                                    sourceFilter = source
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 1)
            }

            HStack(spacing: 6) {
                ForEach(MenuBarProtocolFilter.allCases, id: \.self) { filter in
                    MenuBarProtocolFilterChip(
                        label: filter.rawValue,
                        isSelected: protocolFilter == filter,
                        action: {
                            withAnimation(menuBarSelectionSpring) {
                                protocolFilter = filter
                            }
                        }
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }
}

// MARK: - Search Header
struct MenuBarSearchHeader: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: Theme.Icon.search)
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            TextField("Search ports...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: Theme.Icon.clearSearch)
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.Surface.headerTint)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Size.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .cornerRadius(Theme.Size.cornerRadius)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

// MARK: - Port Section
struct MenuBarPortSection: View {
    let title: String
    let icon: String
    let iconColor: Color
    let ports: [PortProcess]
    let onKill: (Int) -> Void
    let onCopy: (PortProcess) -> Void
    var tunnelDetailProvider: ((PortProcess) -> String?)? = nil
    var tunnelNameProvider: ((PortProcess) -> String?)? = nil
    var namespaceProvider: ((PortProcess) -> String)? = nil
    var isLocalSection: Bool = true
    var statusColor: Color = Theme.Status.connected

    @State private var isExpanded = true

    private var namespaceGroups: [(namespace: String, ports: [PortProcess])]? {
        guard let provider = namespaceProvider else { return nil }
        let grouped = Dictionary(grouping: ports, by: provider)
        guard grouped.keys.count > 1 else { return nil }
        return grouped.sorted { $0.key < $1.key }.map { (namespace: $0.key, ports: $0.value) }
    }

    var body: some View {
        VStack(spacing: 2) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: Theme.Size.sectionIconSize, weight: .medium))
                        .foregroundColor(iconColor)
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: isExpanded ? Theme.Icon.chevronDown : Theme.Icon.chevronRight)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if isExpanded {
                if let groups = namespaceGroups {
                    ForEach(groups, id: \.namespace) { group in
                        MenuBarNamespaceSubSection(
                            namespace: group.namespace,
                            ports: group.ports,
                            onKill: onKill,
                            onCopy: onCopy,
                            tunnelDetailProvider: tunnelDetailProvider,
                            tunnelNameProvider: tunnelNameProvider,
                            isLocal: isLocalSection,
                            statusColor: statusColor
                        )
                    }
                } else {
                    ForEach(ports, id: \.id) { port in
                        MenuBarDropdownPortRow(
                            port: port,
                            onKill: { onKill(port.port) },
                            onCopy: { onCopy(port) },
                            tunnelDetail: tunnelDetailProvider?(port),
                            tunnelName: tunnelNameProvider?(port),
                            isLocal: isLocalSection,
                            statusColor: statusColor
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Namespace Sub-Section (K8s grouping)
struct MenuBarNamespaceSubSection: View {
    let namespace: String
    let ports: [PortProcess]
    let onKill: (Int) -> Void
    let onCopy: (PortProcess) -> Void
    var tunnelDetailProvider: ((PortProcess) -> String?)? = nil
    var tunnelNameProvider: ((PortProcess) -> String?)? = nil
    var isLocal: Bool = true
    var statusColor: Color = Theme.Status.connected

    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 2) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.Section.kubernetes.opacity(0.7))
                    Text(namespace)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: isExpanded ? Theme.Icon.chevronDown : Theme.Icon.chevronRight)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .padding(.leading, 24)
                .padding(.trailing, 12)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(ports, id: \.id) { port in
                    MenuBarDropdownPortRow(
                        port: port,
                        onKill: { onKill(port.port) },
                        onCopy: { onCopy(port) },
                        indent: true,
                        tunnelDetail: tunnelDetailProvider?(port),
                        tunnelName: tunnelNameProvider?(port),
                        isLocal: isLocal,
                        statusColor: statusColor
                    )
                }
            }
        }
    }
}

// MARK: - Tree Section (grouped by process)
struct MenuBarTreeSection: View {
    let processName: String
    let ports: [PortProcess]
    let onKill: (Int) -> Void
    let onCopy: (PortProcess) -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 2) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "app.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.Action.treeView)
                    Text(processName)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: isExpanded ? Theme.Icon.chevronDown : Theme.Icon.chevronRight)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(ports, id: \.id) { port in
                    MenuBarDropdownPortRow(
                        port: port,
                        onKill: { onKill(port.port) },
                        onCopy: { onCopy(port) },
                        indent: true
                    )
                }
            }
        }
    }
}

// MARK: - Port Row
struct MenuBarDropdownPortRow: View {
    let port: PortProcess
    let onKill: () -> Void
    let onCopy: () -> Void
    var indent: Bool = false
    var tunnelDetail: String? = nil
    var tunnelName: String? = nil
    var isLocal: Bool = true
    var statusColor: Color = Theme.Status.connected

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: Theme.Size.statusDotLarge, height: Theme.Size.statusDotLarge)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if port.isUnixSocket {
                        Text("PID \(port.pid)")
                            .font(.system(size: 12, design: .monospaced))
                            .fontWeight(.medium)
                    } else {
                        Text(":\(port.port)")
                            .font(.system(size: 12, design: .monospaced))
                            .fontWeight(.medium)
                    }

                    Text(port.protocolName.uppercased())
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.Surface.headerTint)
                        .cornerRadius(3)

                    if !indent {
                        Text(tunnelName ?? port.command)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                if let detail = tunnelDetail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if let socketPath = port.socketPath {
                    Text(socketPath)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            if !isLocal {
                // Always-visible red "Stop" pill for tunnel rows
                Button(action: onKill) {
                    Text("Stop")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.Action.kill)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            } else if isHovered {
                Button(action: onCopy) {
                    Image(systemName: Theme.Icon.copy)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.Action.treeView)
                }
                .buttonStyle(.plain)
                .transition(.opacity)

                Button(action: onKill) {
                    Image(systemName: Theme.Icon.kill)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Action.kill)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            } else {
                Text("PID \(port.pid)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding(.leading, indent ? 24 : 12)
        .padding(.trailing, 12)
        .padding(.vertical, 7)
        .background(isHovered ? Theme.Surface.hover : .clear)
        .cornerRadius(Theme.Size.cornerRadiusSmall)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}

// MARK: - Empty State
struct MenuBarEmptyState: View {
    let hasSearch: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: hasSearch ? Theme.Icon.search : Theme.Icon.checkmark)
                .font(.system(size: 24))
                .foregroundColor(hasSearch ? .secondary : Theme.Status.connected)
            Text(hasSearch ? "No matching ports" : "No Active Ports")
                .font(.system(size: 13, weight: .medium))
            Text(hasSearch ? "Try a different search or filter" : "All ports are available")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Quick Actions
struct MenuBarQuickActions: View {
    let onRefresh: () -> Void
    let onToggleTreeView: () -> Void
    let isTreeView: Bool
    let onKillAll: () -> Void
    let hasActivePorts: Bool

    var body: some View {
        MenuBarActionSection {
            MenuBarActionButton(
                label: "Refresh",
                shortcut: "R",
                icon: Theme.Icon.refresh,
                iconColor: Theme.Action.refresh,
                labelColor: .primary,
                action: onRefresh
            )

            MenuBarActionDivider()

            MenuBarActionButton(
                label: isTreeView ? "List View" : "Tree View",
                shortcut: "T",
                icon: isTreeView ? "list.bullet" : Theme.Icon.treeView,
                iconColor: Theme.Action.treeView,
                labelColor: .primary,
                action: onToggleTreeView
            )

            if hasActivePorts {
                MenuBarActionDivider()

                MenuBarActionButton(
                    label: "Kill All",
                    shortcut: "K",
                    icon: Theme.Icon.killAll,
                    iconColor: Theme.Action.kill,
                    labelColor: Theme.Action.kill,
                    action: onKillAll
                )
            }
        }
    }
}

// MARK: - Bottom Actions
struct MenuBarBottomActions: View {
    let onOpenMainWindow: () -> Void
    let onSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        MenuBarActionSection {
            MenuBarActionButton(
                label: "Open PortPilot",
                shortcut: "O",
                icon: Theme.Icon.openWindow,
                iconColor: Theme.Action.treeView,
                labelColor: .primary,
                action: onOpenMainWindow
            )

            MenuBarActionDivider()

            MenuBarActionButton(
                label: "Settings",
                shortcut: ",",
                icon: Theme.Icon.settings,
                iconColor: .secondary,
                labelColor: .primary,
                action: onSettings
            )

            MenuBarActionButton(
                label: "Quit",
                shortcut: "Q",
                icon: Theme.Icon.quit,
                iconColor: .secondary,
                labelColor: .primary,
                action: onQuit
            )
        }
    }
}

struct MenuBarSourceFilterChip: View {
    let label: String
    let count: Int
    let icon: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isSelected ? .white : tint)
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                if isSelected || label == "All" {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(isSelected ? Color.white.opacity(0.8) : .secondary.opacity(0.72))
                }
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(isSelected ? Theme.Badge.accentBackground : Theme.Surface.groupedFill)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.14) : Theme.Surface.groupedStroke, lineWidth: 1)
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

struct MenuBarProtocolFilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(isSelected ? Theme.Badge.accentBackground : Theme.Surface.groupedFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(isSelected ? Color.white.opacity(0.14) : Theme.Surface.groupedStroke, lineWidth: 1)
                )
                .cornerRadius(9)
        }
        .buttonStyle(.plain)
    }
}

struct MenuBarUtilityChip: View {
    let label: String
    let icon: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(isSelected ? .white : tint)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(isSelected ? tint : Theme.Surface.groupedFill)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.14) : Theme.Surface.groupedStroke, lineWidth: 1)
            )
            .cornerRadius(9)
        }
        .buttonStyle(.plain)
    }
}

struct MenuBarClearChip: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: Theme.Icon.clearSearch)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
                .background(Theme.Surface.groupedFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Theme.Surface.groupedStroke, lineWidth: 1)
                )
                .cornerRadius(9)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Action Button
struct MenuBarActionButton: View {
    let label: String
    let shortcut: String
    let icon: String
    var iconColor: Color = .primary
    var labelColor: Color = .primary
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: Theme.Size.actionIconSize))
                    .foregroundColor(iconColor)
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(labelColor)
                Spacer()
                Text("\u{2318}\(shortcut)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 34)
            .padding(.horizontal, 12)
            .background(isHovered ? Theme.Surface.rowHover : .clear)
            .cornerRadius(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}

struct MenuBarActionSection<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.Surface.groupedFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.Surface.groupedStroke, lineWidth: 1)
        )
    }
}

struct MenuBarActionDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 42)
            .padding(.trailing, 10)
    }
}

struct MenuBarFooterLink: View {
    let label: String
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isHovered ? Theme.Action.sponsors : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.top, 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Socket Row (for Sockets tab)
struct MenuBarSocketRow: View {
    let process: PortProcess
    let processType: ProcessType
    let onKill: () -> Void
    let onCopy: () -> Void

    @State private var isHovered = false

    private var typeColor: Color {
        switch processType {
        case .system: return Theme.Classification.system
        case .userApp: return Theme.Classification.userApp
        case .developerTool: return Theme.Classification.developerTool
        case .other: return Theme.Classification.other
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(typeColor)
                .frame(width: Theme.Size.statusDotLarge, height: Theme.Size.statusDotLarge)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(process.command)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    Text("PID \(process.pid)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(typeColor.opacity(0.8))
                        .cornerRadius(4)

                    Text(processType.rawValue)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.Surface.headerTint)
                        .cornerRadius(3)
                }

                if let socketPath = process.socketPath {
                    Text(socketPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if let fullCmd = process.fullCommand {
                    Text(fullCmd)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            if isHovered {
                Button(action: onCopy) {
                    Image(systemName: Theme.Icon.copy)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.Action.treeView)
                }
                .buttonStyle(.plain)

                Button(action: onKill) {
                    Image(systemName: Theme.Icon.kill)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Action.kill)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isHovered ? Theme.Surface.hover : .clear)
        .cornerRadius(Theme.Size.cornerRadiusSmall)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}
