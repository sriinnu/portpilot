import SwiftUI
import PortManagerLib

// MARK: - Protocol Filter for Menu Bar
enum MenuBarProtocolFilter: String, CaseIterable {
    case all = "All"
    case tcp = "TCP"
    case udp = "UDP"
}

// MARK: - Menu Bar Dropdown View
struct MenuBarDropdownView: View {
    @ObservedObject var viewModel: PortViewModel
    let onOpenMainWindow: () -> Void
    let onQuit: () -> Void
    let onDismiss: () -> Void
    let onOpenSettings: () -> Void
    let onSponsors: () -> Void

    @State private var searchText = ""
    @State private var protocolFilter: MenuBarProtocolFilter = .all
    @State private var showTreeView = false

    private var filteredPorts: [PortProcess] {
        var result = viewModel.ports

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

    private var groupedPorts: [(process: String, ports: [PortProcess])] {
        let dict = Dictionary(grouping: filteredPorts, by: { $0.command })
        return dict.sorted { $0.key < $1.key }.map { (process: $0.key, ports: $0.value) }
    }

    private var groupedFilteredPorts: [ConnectionType: [PortProcess]] {
        Dictionary(grouping: filteredPorts) { viewModel.connectionType(for: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar + count badge
            MenuBarSearchHeader(
                searchText: $searchText,
                portCount: viewModel.ports.count
            )

            // Protocol filter pills
            MenuBarProtocolPicker(selected: $protocolFilter)

            Divider().padding(.vertical, 2)

            // Port sections
            Group {
                if filteredPorts.isEmpty {
                    MenuBarEmptyState(hasSearch: !searchText.isEmpty || protocolFilter != .all)
                } else if showTreeView {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(groupedPorts, id: \.process) { group in
                                MenuBarTreeSection(
                                    processName: group.process,
                                    ports: group.ports,
                                    onKill: { port in viewModel.killPort(port) },
                                    onCopy: { port in viewModel.copyPortInfo(port) }
                                )
                            }
                        }
                        .padding(.vertical, 6)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(ConnectionType.allCases) { type in
                                let portsForType = groupedFilteredPorts[type] ?? []
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
            }
            .frame(minHeight: 120, maxHeight: 280)

            Divider().padding(.vertical, 2)

            // Quick actions
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

            Divider().padding(.vertical, 2)

            // Bottom actions
            MenuBarBottomActions(
                onOpenMainWindow: {
                    onDismiss()
                    onOpenMainWindow()
                },
                onSponsors: {
                    onDismiss()
                    onSponsors()
                },
                onSettings: {
                    onDismiss()
                    onOpenSettings()
                },
                onQuit: onQuit
            )
        }
        .frame(width: 320)
    }
}

// MARK: - Protocol Picker
struct MenuBarProtocolPicker: View {
    @Binding var selected: MenuBarProtocolFilter

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MenuBarProtocolFilter.allCases, id: \.self) { filter in
                Button(action: { selected = filter }) {
                    Text(filter.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(selected == filter ? .white : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            selected == filter
                                ? Theme.Badge.accentBackground
                                : Color(nsColor: .quaternaryLabelColor).opacity(0.5)
                        )
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Search Header
struct MenuBarSearchHeader: View {
    @Binding var searchText: String
    let portCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: Theme.Icon.appLogo)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.Action.treeView, Theme.Section.kubernetes],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

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
            .padding(.vertical, 5)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
            .cornerRadius(Theme.Size.cornerRadius)

            Text("\(portCount)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.Badge.accentText)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Theme.Badge.accentBackground)
                .cornerRadius(Theme.Size.cornerRadiusSmall)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
                    Text("(\(ports.count))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
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
                    ForEach(ports, id: \.port) { port in
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
                    Text("(\(ports.count))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.6))
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
                ForEach(ports, id: \.port) { port in
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
                    Text("(\(ports.count))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
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
                ForEach(ports, id: \.port) { port in
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
                    Text(":\(port.port)")
                        .font(.system(size: 12, design: .monospaced))
                        .fontWeight(.medium)

                    Text(port.protocolName.uppercased())
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
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
        VStack(spacing: 2) {
            MenuBarActionButton(
                label: "Refresh",
                shortcut: "R",
                icon: Theme.Icon.refresh,
                iconColor: Theme.Action.refresh,
                labelColor: .primary,
                action: onRefresh
            )

            MenuBarActionButton(
                label: isTreeView ? "List View" : "Tree View",
                shortcut: "T",
                icon: isTreeView ? "list.bullet" : Theme.Icon.treeView,
                iconColor: Theme.Action.treeView,
                labelColor: .primary,
                action: onToggleTreeView
            )

            if hasActivePorts {
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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

// MARK: - Bottom Actions
struct MenuBarBottomActions: View {
    let onOpenMainWindow: () -> Void
    let onSponsors: () -> Void
    let onSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            MenuBarActionButton(
                label: "Open PortPilot",
                shortcut: "O",
                icon: Theme.Icon.openWindow,
                iconColor: Theme.Action.treeView,
                labelColor: .primary,
                action: onOpenMainWindow
            )

            MenuBarActionButton(
                label: "Sponsors",
                shortcut: "S",
                icon: Theme.Icon.sponsors,
                iconColor: Theme.Action.sponsors,
                labelColor: Theme.Action.sponsors,
                action: onSponsors
            )

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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
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
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(labelColor)
                Spacer()
                Text("\u{2318}\(shortcut)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isHovered ? Theme.Surface.hover : .clear)
            .cornerRadius(Theme.Size.cornerRadiusSmall)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}
