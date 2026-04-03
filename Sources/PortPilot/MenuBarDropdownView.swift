import SwiftUI

private let menuBarSelectionSpring = Animation.spring(response: 0.26, dampingFraction: 0.84, blendDuration: 0.1)

// MARK: - Protocol Filter for Menu Bar
enum MenuBarProtocolFilter: String, CaseIterable {
    case all = "All"
    case tcp = "TCP"
    case udp = "UDP"
}

// MARK: - Alert State
enum AlertState {
    case normal
    case warning
    case critical

    var isAlert: Bool {
        self != .normal
    }
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
        case connections = "Connections"
        case schedules = "Schedules"
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

    // MARK: - Alert State

    private var alertState: AlertState {
        let blocklistedCount = viewModel.allConnections.filter { $0.isBlocklisted }.count
        let suspiciousCount = viewModel.connectionsGrouped.filter { $0.totalCount > 50 }.count
        if blocklistedCount > 0 || suspiciousCount > 0 {
            return .critical
        }
        return .normal
    }

    private var alertCount: Int {
        let blocklistedCount = viewModel.allConnections.filter { $0.isBlocklisted }.count
        let suspiciousCount = viewModel.connectionsGrouped.filter { $0.totalCount > 50 }.count
        return blocklistedCount + suspiciousCount
    }

    private var statusDotColor: Color {
        switch alertState {
        case .normal: return Theme.Alert.dotActive
        case .warning: return Theme.Alert.dotWarning
        case .critical: return Theme.Alert.dotCritical
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Status bar (Dynamic Island style)
            MenuBarStatusBar(
                portCount: networkPorts.count,
                socketCount: socketProcesses.count,
                alertCount: alertCount,
                alertState: alertState,
                onSettingsTap: onOpenSettings
            )

            // Search bar + count badge
            MenuBarSearchHeader(
                searchText: $searchText
            )

            // Tab switcher: Ports | Sockets | Connections
            HStack(spacing: 12) {
                MenuBarTabButton(
                    tab: .ports,
                    count: networkPorts.count,
                    isActive: activeTab == .ports,
                    icon: Theme.Icon.portsTab,
                    onTap: {
                        withAnimation(menuBarSelectionSpring) { activeTab = .ports }
                    }
                )
                MenuBarTabButton(
                    tab: .sockets,
                    count: socketProcesses.count,
                    isActive: activeTab == .sockets,
                    icon: Theme.Icon.socketsTab,
                    onTap: {
                        withAnimation(menuBarSelectionSpring) { activeTab = .sockets }
                    }
                )
                MenuBarTabButton(
                    tab: .connections,
                    count: viewModel.allConnections.count,
                    isActive: activeTab == .connections,
                    icon: "network",
                    onTap: {
                        withAnimation(menuBarSelectionSpring) { activeTab = .connections }
                        // Always refresh when switching to Connections tab to ensure fresh data
                        viewModel.refreshAllConnections()
                    }
                )
                MenuBarTabButton(
                    tab: .schedules,
                    count: viewModel.cronjobs.count,
                    isActive: activeTab == .schedules,
                    icon: "clock",
                    onTap: {
                        withAnimation(menuBarSelectionSpring) { activeTab = .schedules }
                        // Refresh cronjobs when switching to Schedules tab
                        viewModel.refreshCronjobs()
                    }
                )
            }
            .padding(5)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.Surface.headerTint)
            )
            .padding(.horizontal, 14)
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
                } else if activeTab == .connections {
                    // Connections tab - show established connections grouped by process
                    if viewModel.isLoadingAllConnections {
                        VStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Scanning connections...")
                                .font(appSettings.appFont(size: appSettings.fontSize - 1))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.allConnections.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "network")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary)
                            Text("No Active Connections")
                                .font(appSettings.appFont(size: appSettings.fontSize + 1, weight: .medium))
                            Text("Active outbound connections appear here")
                                .font(appSettings.appFont(size: appSettings.fontSize - 1))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Blocklist warning banner
                        let blocklistedCount = viewModel.allConnections.filter { $0.isBlocklisted }.count
                        if blocklistedCount > 0 {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12))
                                Text("🚨 \(blocklistedCount) connection(s) to blocklisted host(s)")
                                    .font(appSettings.appFont(size: appSettings.fontSize - 1, weight: .semibold))
                                Spacer()
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Theme.Action.kill.opacity(0.9))
                            )
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                        }
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(viewModel.connectionsGrouped, id: \.processName) { group in
                                    MenuBarConnectionSection(
                                        processName: group.processName,
                                        connections: group.connections,
                                        totalCount: group.totalCount,
                                        onKill: { pid in viewModel.killProcess(pid: pid) }
                                    )
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                } else if activeTab == .schedules {
                    // Schedules tab - show cronjobs
                    if viewModel.isLoadingCronjobs {
                        VStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Scanning cronjobs...")
                                .font(appSettings.appFont(size: appSettings.fontSize - 1))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.cronjobs.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "clock")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary)
                            Text("No Cronjobs Found")
                                .font(appSettings.appFont(size: appSettings.fontSize + 1, weight: .medium))
                            Text("User and system cronjobs appear here")
                                .font(appSettings.appFont(size: appSettings.fontSize - 1))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(viewModel.cronjobs) { job in
                                    MenuBarCronjobRow(cronjob: job)
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
                                .font(appSettings.appFont(size: appSettings.fontSize + 1, weight: .medium))
                            Text("Local app daemons with Unix sockets appear here")
                                .font(appSettings.appFont(size: appSettings.fontSize - 1))
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
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .frame(width: 380)
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

// MARK: - Status Bar (Dynamic Island Style)
struct MenuBarStatusBar: View {
    let portCount: Int
    let socketCount: Int
    let alertCount: Int
    let alertState: AlertState
    let onSettingsTap: () -> Void

    @State private var isPulsing = false
    @ObservedObject private var appSettings = AppSettings.shared

    private var statusDotColor: Color {
        switch alertState {
        case .normal: return Theme.Alert.dotActive
        case .warning: return Theme.Alert.dotWarning
        case .critical: return Theme.Alert.dotCritical
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            if alertState.isAlert {
                // Alert state - prominent warning
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("⚠ ALERT")
                        .font(appSettings.appFont(size: 11, weight: .bold))
                    if alertCount > 0 {
                        Text("(\(alertCount))")
                            .font(appSettings.appFont(size: 11, weight: .medium))
                    }
                }
                .foregroundColor(Theme.Alert.criticalText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Theme.Alert.criticalBackground)
                )
                .scaleEffect(isPulsing ? 1.02 : 1.0)
            } else {
                // Normal state - live counts
                HStack(spacing: 8) {
                    // Pulsing status dot
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 7, height: 7)
                        .scaleEffect(isPulsing ? 1.3 : 1.0)
                        .animation(
                            .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                            value: isPulsing
                        )

                    // Port count
                    HStack(spacing: 3) {
                        Text("\(portCount)")
                            .font(appSettings.appFont(size: 12, weight: .semibold))
                        Text("Active")
                            .font(appSettings.appFont(size: 11))
                    }
                    .foregroundColor(.primary)

                    Text("|")
                        .foregroundColor(.secondary)

                    // Socket count
                    HStack(spacing: 3) {
                        Text("\(socketCount)")
                            .font(appSettings.appFont(size: 12, weight: .semibold))
                        Text("Sockets")
                            .font(appSettings.appFont(size: 11))
                    }
                    .foregroundColor(.secondary)

                    if alertCount > 0 {
                        Text("|")
                            .foregroundColor(.secondary)

                        HStack(spacing: 3) {
                            Text("\(alertCount)")
                                .font(appSettings.appFont(size: 12, weight: .bold))
                                .foregroundColor(Theme.Alert.dotCritical)
                            Text("Alert\(alertCount == 1 ? "" : "s")")
                                .font(appSettings.appFont(size: 11))
                                .foregroundColor(Theme.Alert.dotCritical)
                        }
                    }
                }
            }

            Spacer()

            // Settings gear
            Button(action: onSettingsTap) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .onTapGesture {
                onSettingsTap()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Theme.Surface.headerTint
                .opacity(0.95)
        )
        .onAppear {
            if alertState.isAlert {
                isPulsing = true
            }
        }
        .onChange(of: alertState) { newValue in
            isPulsing = newValue.isAlert
        }
    }
}

// MARK: - Search Header
struct MenuBarSearchHeader: View {
    @Binding var searchText: String
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: Theme.Icon.search)
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            TextField("Search ports...", text: $searchText)
                .textFieldStyle(.plain)
                .font(appSettings.appFont(size: appSettings.fontSize + 1))
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: Theme.Icon.clearSearch)
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Surface.headerTint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .padding(.horizontal, 14)
        .padding(.top, 12)
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

    @ObservedObject private var appSettings = AppSettings.shared
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
                        .font(appSettings.appFont(size: appSettings.fontSize - 1, weight: .semibold))
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

    @ObservedObject private var appSettings = AppSettings.shared
    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 2) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.Section.kubernetes.opacity(0.7))
                    Text(namespace)
                        .font(appSettings.appFont(size: appSettings.fontSize - 2, weight: .medium))
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

    @ObservedObject private var appSettings = AppSettings.shared
    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 2) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "app.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.Action.treeView)
                    Text(processName)
                        .font(appSettings.appFont(size: appSettings.fontSize - 1, weight: .semibold))
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

    @ObservedObject private var appSettings = AppSettings.shared
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
                            .font(appSettings.appMonoFont(size: appSettings.fontSize, weight: .medium))
                    } else {
                        Text(":\(port.port)")
                            .font(appSettings.appMonoFont(size: appSettings.fontSize, weight: .medium))
                    }

                    Text(port.protocolName.uppercased())
                        .font(appSettings.appMonoFont(size: max(appSettings.fontSize - 3, 8), weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.Surface.headerTint)
                        .cornerRadius(3)

                    // CPU badge — always visible, heat-map pill for active, muted for idle
                    if let cpu = port.cpuUsage {
                        if cpu > 0.1 {
                            Text(String(format: "%.1f%%", cpu))
                                .font(appSettings.appMonoFont(size: max(appSettings.fontSize - 3, 8), weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(cpuHeatColor(cpu)))
                                .shadow(color: cpuHeatColor(cpu).opacity(0.35), radius: 3, y: 1)
                        } else {
                            Text("0%")
                                .font(appSettings.appMonoFont(size: max(appSettings.fontSize - 3, 8), weight: .medium))
                                .foregroundColor(.secondary.opacity(0.5))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1))
                        }
                    }

                    // Memory badge
                    if let mem = port.memoryMB {
                        Text(formatMemory(mem))
                            .font(appSettings.appMonoFont(size: max(appSettings.fontSize - 3, 8), weight: .medium))
                            .foregroundColor(.secondary.opacity(0.7))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1))
                    }

                    if !indent {
                        Text(tunnelName ?? port.command)
                            .font(appSettings.appFont(size: appSettings.fontSize))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                if let detail = tunnelDetail {
                    Text(detail)
                        .font(appSettings.appFont(size: appSettings.fontSize - 2))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if let socketPath = port.socketPath {
                    Text(socketPath)
                        .font(appSettings.appMonoFont(size: appSettings.fontSize - 2))
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
                        .font(appSettings.appFont(size: max(appSettings.fontSize - 3, 8), weight: .semibold))
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
                    .font(appSettings.appMonoFont(size: appSettings.fontSize - 2))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding(.leading, indent ? 26 : 14)
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Theme.Surface.hover : .clear)
                .shadow(color: isHovered ? Color.black.opacity(0.07) : .clear, radius: 6, y: 2)
        )
        .contentShape(Rectangle())
        .scaleEffect(isHovered ? 1.008 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) { isHovered = hovering }
        }
    }

    private func formatMemory(_ mb: Double) -> String {
        if mb >= 1024 { return String(format: "%.1fG", mb / 1024.0) }
        if mb >= 10 { return String(format: "%.0fM", mb) }
        return String(format: "%.1fM", mb)
    }

    /// Smooth heat-map: 0% cool teal → 25% blue → 50% amber → 75% orange → 100% red
    private func cpuHeatColor(_ usage: Double) -> Color {
        let t = min(max(usage / 100.0, 0), 1)
        let r: Double, g: Double, b: Double
        if t < 0.25 {
            // Teal → Blue
            let p = t / 0.25
            r = 0.18 + p * 0.12;  g = 0.62 - p * 0.14;  b = 0.70 - p * 0.02
        } else if t < 0.50 {
            // Blue → Amber
            let p = (t - 0.25) / 0.25
            r = 0.30 + p * 0.58;  g = 0.48 + p * 0.14;  b = 0.68 - p * 0.52
        } else if t < 0.75 {
            // Amber → Orange
            let p = (t - 0.50) / 0.25
            r = 0.88 + p * 0.07;  g = 0.62 - p * 0.22;  b = 0.16 - p * 0.04
        } else {
            // Orange → Red
            let p = (t - 0.75) / 0.25
            r = 0.95 - p * 0.05;  g = 0.40 - p * 0.18;  b = 0.12 + p * 0.08
        }
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Empty State
struct MenuBarEmptyState: View {
    let hasSearch: Bool
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: hasSearch ? Theme.Icon.search : Theme.Icon.checkmark)
                .font(.system(size: 24))
                .foregroundColor(hasSearch ? .secondary : Theme.Status.connected)
            Text(hasSearch ? "No matching ports" : "No Active Ports")
                .font(appSettings.appFont(size: appSettings.fontSize + 1, weight: .medium))
            Text(hasSearch ? "Try a different search or filter" : "All ports are available")
                .font(appSettings.appFont(size: appSettings.fontSize - 1))
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

    @State private var confirmingKillAll = false

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
                    label: confirmingKillAll ? "Confirm Kill All?" : "Kill All",
                    shortcut: confirmingKillAll ? "Y" : "K",
                    icon: confirmingKillAll ? "exclamationmark.triangle.fill" : Theme.Icon.killAll,
                    iconColor: confirmingKillAll ? .orange : Theme.Action.kill,
                    labelColor: confirmingKillAll ? .orange : Theme.Action.kill,
                    action: {
                        if confirmingKillAll {
                            confirmingKillAll = false
                            onKillAll()
                        } else {
                            confirmingKillAll = true
                            // Auto-cancel after 3 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                confirmingKillAll = false
                            }
                        }
                    }
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
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isSelected ? .white : tint)
                Text(label)
                    .font(appSettings.appFont(size: appSettings.fontSize - 1, weight: .semibold))
                if isSelected || label == "All" {
                    Text("\(count)")
                        .font(appSettings.appMonoFont(size: appSettings.fontSize - 2, weight: .bold))
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
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(appSettings.appFont(size: appSettings.fontSize - 1, weight: .semibold))
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(isSelected ? Theme.Badge.accentBackground : Theme.Surface.groupedFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
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
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(appSettings.appFont(size: appSettings.fontSize - 1, weight: .semibold))
            }
            .foregroundColor(isSelected ? .white : tint)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(isSelected ? tint : Theme.Surface.groupedFill)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
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

    @ObservedObject private var appSettings = AppSettings.shared
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: Theme.Size.actionIconSize))
                    .foregroundColor(iconColor)
                    .frame(width: 18)
                Text(label)
                    .font(appSettings.appFont(size: appSettings.fontSize + 1))
                    .foregroundColor(labelColor)
                Spacer()
                Text("\u{2318}\(shortcut)")
                    .font(appSettings.appFont(size: appSettings.fontSize - 1))
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
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.Surface.groupedFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.Surface.groupedStroke, lineWidth: 0.5)
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

    @ObservedObject private var appSettings = AppSettings.shared
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(appSettings.appFont(size: appSettings.fontSize - 1, weight: .medium))
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

    @ObservedObject private var appSettings = AppSettings.shared
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
                        .font(appSettings.appFont(size: appSettings.fontSize, weight: .medium))
                        .lineLimit(1)

                    Text("PID \(process.pid)")
                        .font(appSettings.appMonoFont(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(typeColor.opacity(0.8))
                        .cornerRadius(4)

                    Text(processType.rawValue)
                        .font(appSettings.appFont(size: max(appSettings.fontSize - 4, 7), weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.Surface.headerTint)
                        .cornerRadius(3)

                    if let cpu = process.cpuUsage {
                        if cpu > 0.1 {
                            Text(String(format: "%.1f%%", cpu))
                                .font(appSettings.appMonoFont(size: max(appSettings.fontSize - 3, 8), weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(socketCpuHeatColor(cpu)))
                                .shadow(color: socketCpuHeatColor(cpu).opacity(0.35), radius: 3, y: 1)
                        } else {
                            Text("0%")
                                .font(appSettings.appMonoFont(size: max(appSettings.fontSize - 3, 8), weight: .medium))
                                .foregroundColor(.secondary.opacity(0.5))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1))
                        }
                    }
                }

                if let socketPath = process.socketPath {
                    Text(socketPath)
                        .font(appSettings.appMonoFont(size: appSettings.fontSize - 2))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if let fullCmd = process.fullCommand {
                    Text(fullCmd)
                        .font(appSettings.appMonoFont(size: appSettings.fontSize - 2))
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

    private func socketCpuHeatColor(_ usage: Double) -> Color {
        let t = min(max(usage / 100.0, 0), 1)
        let r: Double, g: Double, b: Double
        if t < 0.25 {
            let p = t / 0.25
            r = 0.18 + p * 0.12;  g = 0.62 - p * 0.14;  b = 0.70 - p * 0.02
        } else if t < 0.50 {
            let p = (t - 0.25) / 0.25
            r = 0.30 + p * 0.58;  g = 0.48 + p * 0.14;  b = 0.68 - p * 0.52
        } else if t < 0.75 {
            let p = (t - 0.50) / 0.25
            r = 0.88 + p * 0.07;  g = 0.62 - p * 0.22;  b = 0.16 - p * 0.04
        } else {
            let p = (t - 0.75) / 0.25
            r = 0.95 - p * 0.05;  g = 0.40 - p * 0.18;  b = 0.12 + p * 0.08
        }
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Cronjob Row (for Schedules tab)
struct MenuBarCronjobRow: View {
    let cronjob: CronjobEntry

    @ObservedObject private var appSettings = AppSettings.shared
    @State private var isHovered = false

    private var sourceColor: Color {
        cronjob.source == "user" ? Theme.Classification.userApp : Theme.Classification.system
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    var body: some View {
        HStack(spacing: 8) {
            // Schedule info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(cronjob.scheduleHuman ?? cronjob.schedule)
                        .font(appSettings.appFont(size: appSettings.fontSize, weight: .medium))
                        .foregroundColor(.yellow)
                        .lineLimit(1)

                    if let user = cronjob.user {
                        Text(user)
                            .font(appSettings.appFont(size: max(appSettings.fontSize - 3, 8), weight: .medium))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(3)
                    }
                }

                Text(cronjob.command)
                    .font(appSettings.appMonoFont(size: appSettings.fontSize - 2))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Next run time
            if let nextRun = cronjob.nextRun {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Next")
                        .font(appSettings.appFont(size: max(appSettings.fontSize - 4, 7)))
                        .foregroundColor(.secondary)
                    Text(Self.dateFormatter.string(from: nextRun))
                        .font(appSettings.appMonoFont(size: appSettings.fontSize - 1, weight: .medium))
                        .foregroundColor(.cyan)
                }
            }

            // Source badge
            Text(cronjob.source == "user" ? "user" : "sys")
                .font(appSettings.appFont(size: max(appSettings.fontSize - 4, 7), weight: .bold))
                .foregroundColor(sourceColor)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(sourceColor.opacity(0.2))
                .cornerRadius(3)
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

// MARK: - Tab Button
struct MenuBarTabButton: View {
    let tab: MenuBarDropdownView.MenuBarTab
    let count: Int
    let isActive: Bool
    let icon: String
    let onTap: () -> Void

    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(tab.rawValue)
                    .font(appSettings.appFont(size: appSettings.fontSize + 1, weight: .semibold))
                Text("\(count)")
                    .font(appSettings.appMonoFont(size: appSettings.fontSize - 1, weight: .bold))
                    .foregroundColor(isActive ? .white.opacity(0.7) : .secondary.opacity(0.6))
            }
            .foregroundColor(isActive ? .white : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                isActive
                    ? Theme.Badge.accentBackground
                    : Color.clear
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isActive ? Color.white.opacity(0.14) : Color.clear,
                        lineWidth: 1
                    )
            )
            .cornerRadius(12)
            .animation(menuBarSelectionSpring, value: isActive)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Connection Section (grouped by process)
struct MenuBarConnectionSection: View {
    let processName: String
    let connections: [EstablishedConnection]
    let totalCount: Int
    let onKill: (Int) -> Void

    @ObservedObject private var appSettings = AppSettings.shared
    @State private var isExpanded = true

    private var isSuspicious: Bool { totalCount > 50 }
    private var hasBlocklisted: Bool { connections.contains { $0.isBlocklisted } }

    var body: some View {
        VStack(spacing: 2) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "network")
                        .font(.system(size: 11))
                        .foregroundColor(hasBlocklisted || isSuspicious ? Theme.Action.kill : Theme.Action.treeView)
                    Text(processName)
                        .font(appSettings.appFont(size: appSettings.fontSize - 1, weight: .semibold))
                        .foregroundColor(hasBlocklisted || isSuspicious ? Theme.Action.kill : .primary)
                    if hasBlocklisted {
                        Text("🚨 \(totalCount)")
                            .font(appSettings.appMonoFont(size: appSettings.fontSize - 2, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.Action.kill)
                            .cornerRadius(8)
                    } else if isSuspicious {
                        Text("⚠️ \(totalCount)")
                            .font(appSettings.appMonoFont(size: appSettings.fontSize - 2, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.Action.kill)
                            .cornerRadius(8)
                    } else {
                        Text("\(totalCount)")
                            .font(appSettings.appMonoFont(size: appSettings.fontSize - 2, weight: .medium))
                            .foregroundColor(.secondary)
                    }
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
                ForEach(connections, id: \.id) { conn in
                    MenuBarConnectionRow(
                        connection: conn,
                        onKill: { onKill(conn.pid) }
                    )
                }
            }
        }
    }
}

// MARK: - Connection Row
struct MenuBarConnectionRow: View {
    let connection: EstablishedConnection
    let onKill: () -> Void

    @ObservedObject private var appSettings = AppSettings.shared
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connection.isBlocklisted ? Theme.Action.kill : Theme.Status.connected)
                .frame(width: Theme.Size.statusDotLarge, height: Theme.Size.statusDotLarge)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(connection.remoteAddress)
                        .font(appSettings.appMonoFont(size: appSettings.fontSize, weight: connection.isBlocklisted ? .bold : .medium))
                        .foregroundColor(connection.isBlocklisted ? Theme.Action.kill : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if connection.isBlocklisted {
                        Text("🚨")
                            .font(.system(size: 9, weight: .bold))
                    }

                    Text(connection.state)
                        .font(appSettings.appMonoFont(size: max(appSettings.fontSize - 3, 8), weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.Surface.headerTint)
                        .cornerRadius(3)
                }

                HStack(spacing: 4) {
                    Text("PID \(connection.pid)")
                        .font(appSettings.appMonoFont(size: appSettings.fontSize - 2, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(connection.user)
                        .font(appSettings.appMonoFont(size: appSettings.fontSize - 2))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }

            Spacer()

            if isHovered {
                Button(action: onKill) {
                    Text("Kill")
                        .font(appSettings.appFont(size: max(appSettings.fontSize - 3, 8), weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.Action.kill)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(isHovered ? Theme.Surface.hover : .clear)
        .cornerRadius(Theme.Size.cornerRadiusSmall)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) { isHovered = hovering }
        }
    }
}
