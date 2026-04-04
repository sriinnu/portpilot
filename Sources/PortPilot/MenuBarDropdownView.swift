import SwiftUI

private let liquidSpring = Animation.spring(response: 0.26, dampingFraction: 0.84, blendDuration: 0.1)

private struct PointerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}

/// Smooth heat-map: 0% teal → 50% amber → 100% red
private func cpuHeatColor(_ usage: Double) -> Color {
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

private func formatMemory(_ mb: Double) -> String {
    if mb >= 1024 { return String(format: "%.1f GB", mb / 1024.0) }
    if mb >= 10 { return String(format: "%.0f MB", mb) }
    return String(format: "%.1f MB", mb)
}

// MARK: - Protocol Filter
enum MenuBarProtocolFilter: String, CaseIterable {
    case all = "All"
    case tcp = "TCP"
    case udp = "UDP"
}

// MARK: - Alert State
enum AlertState {
    case normal, warning, critical
    var isAlert: Bool { self != .normal }
}

// MARK: - Menu Bar Dropdown View (Liquid Display)
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
    @State private var sourceFilter: PortSourceFilter = .all
    @State private var showAllActivity = false
    @State private var showTreeView = false
    @State private var showMoreMenu = false
    @State private var confirmingKillAll = false

    // MARK: - Data

    private var filteredPorts: [PortProcess] {
        var result = viewModel.ports.filter { !$0.isUnixSocket }
        if protocolFilter != .all {
            result = result.filter { $0.protocolName.lowercased() == protocolFilter.rawValue.lowercased() }
        }
        if sourceFilter != .all {
            result = result.filter { viewModel.matchesSourceFilter(sourceFilter, for: $0) }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.command.lowercased().contains(q) ||
                String($0.port).contains(q) ||
                String($0.pid).contains(q)
            }
        }
        return result
    }

    private var socketCount: Int {
        viewModel.ports.filter { $0.isUnixSocket }.count
    }

    private var topActivity: [PortProcess] {
        let sorted = filteredPorts.sorted { lhs, rhs in
            let l = (lhs.cpuUsage ?? 0) + (lhs.memoryMB ?? 0)
            let r = (rhs.cpuUsage ?? 0) + (rhs.memoryMB ?? 0)
            return l > r
        }
        return showAllActivity ? sorted : Array(sorted.prefix(3))
    }

    private var processGroups: [(process: String, ports: [PortProcess], pid: Int)] {
        let dict = Dictionary(grouping: filteredPorts, by: { $0.command })
        return dict
            .sorted { $0.value.count > $1.value.count }
            .map { (process: $0.key, ports: $0.value, pid: $0.value.first?.pid ?? 0) }
    }

    private var alertState: AlertState { viewModel.alertState }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerView
            statsView
            searchView
            filterView
            separatorView
            scrollContent
            footerView
        }
        .frame(width: Theme.Liquid.panelWidth)
        .overlay {
            if showMoreMenu {
                Color.black.opacity(0.001)
                    .onTapGesture { showMoreMenu = false }
            }
        }
        .overlay(alignment: .topTrailing) { moreMenuView }
        .animation(.easeOut(duration: 0.15), value: showMoreMenu)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(Theme.Liquid.headerIcon)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.Liquid.accentPurpleMuted))

            Text("PortPilot")
                .font(appSettings.appFont(size: 16, weight: .bold))
                .foregroundColor(Theme.Liquid.headerText)

            Spacer()

            HStack(spacing: 2) {
                headerBtn(icon: "arrow.clockwise") {
                    viewModel.refreshPorts()
                    viewModel.refreshAllConnections()
                }
                headerBtn(icon: "gearshape") {
                    onDismiss()
                    onOpenSettings()
                }
                headerBtn(icon: "ellipsis") {
                    showMoreMenu.toggle()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private func headerBtn(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.Liquid.subtitleText)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(PointerButtonStyle())
    }

    // MARK: - Stats Line

    private var statsView: some View {
        HStack(spacing: 0) {
            statItem(dot: statusDotColor, value: filteredPorts.count, label: "Active", showDot: true)
            statSeparator
            statItem(icon: "point.3.connected.trianglepath.dotted", value: socketCount, label: "Sockets")
            statSeparator
            statItem(icon: "globe", value: viewModel.allConnections.count, label: "Connections")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var statusDotColor: Color {
        switch alertState {
        case .normal: return Theme.Alert.dotActive
        case .warning: return Theme.Alert.dotWarning
        case .critical: return Theme.Alert.dotCritical
        }
    }

    private func statItem(dot: Color? = nil, icon: String? = nil, value: Int, label: String, showDot: Bool = false) -> some View {
        HStack(spacing: 4) {
            if showDot, let dot = dot {
                Circle().fill(dot).frame(width: 7, height: 7)
                    .shadow(color: dot.opacity(0.5), radius: 3)
            }
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.Liquid.accentPurple)
            }
            Text(verbatim: "\(value)")
                .font(appSettings.appFont(size: 13, weight: .bold))
                .foregroundColor(Theme.Liquid.statValue)
            Text(label)
                .font(appSettings.appFont(size: 11))
                .foregroundColor(Theme.Liquid.statLabel)
        }
    }

    private var statSeparator: some View {
        Text("  \u{2022}  ")
            .font(.system(size: 6))
            .foregroundColor(Theme.Liquid.statLabel.opacity(0.3))
    }

    // MARK: - Search

    private var searchView: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.Liquid.subtitleText)
            TextField("Search ports, pid, process...", text: $searchText)
                .textFieldStyle(.plain)
                .font(appSettings.appFont(size: 13))
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Liquid.subtitleText)
                }
                .buttonStyle(PointerButtonStyle())
            } else {
                Text("\u{2318}F")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Liquid.subtitleText.opacity(0.5))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Theme.Liquid.chipBackground))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.Liquid.searchBackground))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.Liquid.searchBorder, lineWidth: 0.5))
        .padding(.horizontal, 14).padding(.bottom, 8)
    }

    // MARK: - Filters

    private var filterView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                filterChip("All", icon: "square.grid.2x2", selected: protocolFilter == .all) {
                    withAnimation(liquidSpring) { protocolFilter = .all }
                }
                filterChip("TCP", selected: protocolFilter == .tcp) {
                    withAnimation(liquidSpring) { protocolFilter = .tcp }
                }
                filterChip("UDP", selected: protocolFilter == .udp) {
                    withAnimation(liquidSpring) { protocolFilter = .udp }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PortSourceFilter.allCases) { src in
                        sourceChip(src.rawValue, icon: src.icon, tint: src.color, selected: sourceFilter == src) {
                            withAnimation(liquidSpring) { sourceFilter = src }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 4)
    }

    private func filterChip(_ label: String, icon: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                }
                Text(label).font(appSettings.appFont(size: 12, weight: .semibold))
            }
            .foregroundColor(selected ? .white : Theme.Liquid.subtitleText)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.Liquid.chipSelectedBackground : Theme.Liquid.chipBackground))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.white.opacity(0.12) : Theme.Liquid.chipBorder, lineWidth: 0.5))
        }
        .buttonStyle(PointerButtonStyle())
    }

    private func sourceChip(_ label: String, icon: String, tint: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .medium)).foregroundColor(selected ? .white : tint)
                Text(label).font(appSettings.appFont(size: 11, weight: .medium))
            }
            .foregroundColor(selected ? .white : Theme.Liquid.statLabel)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? tint.opacity(0.8) : Theme.Liquid.chipBackground))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? tint.opacity(0.3) : Theme.Liquid.chipBorder, lineWidth: 0.5))
        }
        .buttonStyle(PointerButtonStyle())
    }

    // MARK: - Separator

    private var separatorView: some View {
        Theme.Liquid.separator.frame(height: 0.5).padding(.horizontal, 16).padding(.vertical, 6)
    }

    // MARK: - Scrollable Content

    private var scrollContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                if showTreeView {
                    processGroupsSection
                } else {
                    topActivitySection
                    connectionTypeSection
                }
                schedulesSection
                emptySection
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .frame(minHeight: 160, maxHeight: 340)
        .onAppear { viewModel.refreshCronjobs() }
    }

    // MARK: Top Activity

    @ViewBuilder
    private var topActivitySection: some View {
        let activity = topActivity
        if !activity.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.Liquid.accentPurple)
                    Text("Top Activity")
                        .font(appSettings.appFont(size: 13, weight: .semibold))
                        .foregroundColor(Theme.Liquid.headerText)
                    Spacer()
                    Button {
                        withAnimation(liquidSpring) { showAllActivity.toggle() }
                    } label: {
                        HStack(spacing: 3) {
                            Text(showAllActivity ? "Show Less" : "See All")
                                .font(appSettings.appFont(size: 11, weight: .medium))
                            Image(systemName: showAllActivity ? "chevron.up" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(Theme.Liquid.accentPurple)
                    }
                    .buttonStyle(PointerButtonStyle())
                }

                ForEach(activity, id: \.id) { port in
                    LiquidPortRow(
                        port: port,
                        onKill: { viewModel.killPort(port.port) },
                        onCopy: { viewModel.copyPortInfo(port) }
                    )
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.Liquid.sectionBackground))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.Liquid.cardBorder, lineWidth: 0.5))
        }
    }

    // MARK: Connection Type Groups (List View)

    @ViewBuilder
    private var connectionTypeSection: some View {
        let grouped = Dictionary(grouping: filteredPorts) { viewModel.connectionType(for: $0) }
        ForEach(ConnectionType.allCases) { type in
            let portsForType = grouped[type] ?? []
            if !portsForType.isEmpty {
                LiquidConnectionTypeSection(
                    type: type,
                    ports: portsForType,
                    viewModel: viewModel
                )
            }
        }
    }

    // MARK: Process Groups (Tree View)

    @ViewBuilder
    private var processGroupsSection: some View {
        let groups = processGroups
        if !groups.isEmpty {
            LiquidProcessSection(
                title: "Local Processes",
                icon: "folder.fill",
                groups: groups,
                totalCount: filteredPorts.count,
                viewModel: viewModel
            )
        }
    }

    // MARK: Schedules (Cronjobs)

    @ViewBuilder
    private var schedulesSection: some View {
        if !viewModel.cronjobs.isEmpty {
            LiquidSchedulesSection(
                cronjobs: viewModel.cronjobs
            )
        }
    }

    // MARK: Empty State

    @ViewBuilder
    private var emptySection: some View {
        if filteredPorts.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: searchText.isEmpty && protocolFilter == .all && sourceFilter == .all ? "checkmark.circle" : "magnifyingglass")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(searchText.isEmpty ? Theme.Alert.dotActive : Theme.Liquid.subtitleText)
                Text(searchText.isEmpty && protocolFilter == .all && sourceFilter == .all ? "No Active Ports" : "No matching ports")
                    .font(appSettings.appFont(size: 14, weight: .medium))
                    .foregroundColor(Theme.Liquid.headerText)
                Text(searchText.isEmpty && protocolFilter == .all && sourceFilter == .all ? "All ports are available" : "Try a different search or filter")
                    .font(appSettings.appFont(size: 12))
                    .foregroundColor(Theme.Liquid.subtitleText)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 30)
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: 0) {
            // Open App + Tree View
            HStack(spacing: 0) {
                Button {
                    onDismiss()
                    onOpenMainWindow()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "macwindow").font(.system(size: 12, weight: .medium))
                        Text("Open PortPilot App").font(appSettings.appFont(size: 12, weight: .medium))
                        Text("\u{2318}O").font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Liquid.subtitleText.opacity(0.5))
                    }
                    .foregroundColor(Theme.Liquid.headerText)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(PointerButtonStyle())

                Theme.Liquid.separator.frame(width: 0.5, height: 20)

                Button {
                    withAnimation(liquidSpring) { showTreeView.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showTreeView ? "list.bullet" : "list.bullet.indent")
                            .font(.system(size: 12, weight: .medium))
                        Text(showTreeView ? "List View" : "Tree View")
                            .font(appSettings.appFont(size: 12, weight: .medium))
                        Text("\u{2318}T").font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Liquid.subtitleText.opacity(0.5))
                    }
                    .foregroundColor(showTreeView ? Theme.Liquid.accentPurple : Theme.Liquid.headerText)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(PointerButtonStyle())
            }
            .background(Theme.Liquid.footerBackground)
            .overlay(alignment: .top) { Theme.Liquid.footerBorder.frame(height: 0.5) }

            // Sponsor link
            Button {
                onDismiss()
                onSponsors()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.Action.sponsors)
                    Text("Sponsor PortPilot")
                        .font(appSettings.appFont(size: 12, weight: .medium))
                        .foregroundColor(Theme.Action.sponsors)
                    Spacer()
                    Text("by Sriinnu")
                        .font(appSettings.appFont(size: 11, weight: .medium))
                        .foregroundColor(Theme.Liquid.headerText.opacity(0.6))
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            .buttonStyle(PointerButtonStyle())
        }
    }

    // MARK: - More Menu Overlay

    @ViewBuilder
    private var moreMenuView: some View {
        if showMoreMenu {
            VStack(spacing: 2) {
                moreItem("Refresh", icon: "arrow.clockwise", shortcut: "R") {
                    showMoreMenu = false
                    viewModel.refreshPorts()
                    viewModel.refreshAllConnections()
                }
                if !viewModel.ports.isEmpty {
                    moreItem(confirmingKillAll ? "Confirm Kill All?" : "Kill All...", icon: confirmingKillAll ? "exclamationmark.triangle.fill" : "xmark.circle", shortcut: "K", tint: Theme.Action.kill) {
                        if confirmingKillAll {
                            confirmingKillAll = false
                            showMoreMenu = false
                            viewModel.killSelectedPorts(Set(viewModel.ports))
                        } else {
                            confirmingKillAll = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { confirmingKillAll = false }
                        }
                    }
                }
                Divider().padding(.horizontal, 8).padding(.vertical, 2)
                moreItem("Settings", icon: "gearshape", shortcut: ",") {
                    showMoreMenu = false; onDismiss(); onOpenSettings()
                }
                Divider().padding(.horizontal, 8).padding(.vertical, 2)
                moreItem("Quit", icon: "power", shortcut: "Q") { showMoreMenu = false; onQuit() }
            }
            .padding(6).frame(width: 210)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.Liquid.cardBackground)
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 4)
            )
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.Liquid.cardBorder, lineWidth: 0.5))
            .padding(.top, 48).padding(.trailing, 14)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topTrailing)))
            .zIndex(100)
        }
    }

    private func moreItem(_ label: String, icon: String, shortcut: String? = nil, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12, weight: .medium))
                    .foregroundColor(tint ?? Theme.Liquid.subtitleText).frame(width: 16)
                Text(label).font(appSettings.appFont(size: 13)).foregroundColor(tint ?? Theme.Liquid.headerText)
                Spacer()
                if let s = shortcut {
                    Text("\u{2318}\(s)").font(.system(size: 11, design: .rounded))
                        .foregroundColor(Theme.Liquid.subtitleText.opacity(0.4))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(PointerButtonStyle())
    }
}

// MARK: - Port Row (with kill/copy actions)

private struct LiquidPortRow: View {
    let port: PortProcess
    let onKill: () -> Void
    let onCopy: () -> Void
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var isHovered = false

    private var portStr: String { ":\(port.port)" }
    private var pidStr: String { "PID \(port.pid)" }

    var body: some View {
        HStack(spacing: 6) {
            // Status dot
            Circle()
                .fill(Theme.Alert.dotActive)
                .frame(width: 8, height: 8)
                .shadow(color: Theme.Alert.dotActive.opacity(0.4), radius: 3)

            // Port number — verbatim to avoid locale commas
            Text(verbatim: portStr)
                .font(appSettings.appMonoFont(size: 13, weight: .bold))
                .foregroundColor(Theme.Liquid.headerText)
                .lineLimit(1)
                .fixedSize()

            // Protocol badge
            Text(port.protocolName.uppercased())
                .font(appSettings.appMonoFont(size: 8, weight: .bold))
                .foregroundColor(Theme.Liquid.subtitleText)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(Theme.Liquid.chipBackground))
                .fixedSize()

            // Process name — truncate with more room
            Text(port.command)
                .font(appSettings.appFont(size: 11))
                .foregroundColor(Theme.Liquid.subtitleText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            // PID — verbatim
            Text(verbatim: pidStr)
                .font(appSettings.appMonoFont(size: 9))
                .foregroundColor(Theme.Liquid.subtitleText.opacity(0.6))
                .fixedSize()

            // Memory badge
            if let mem = port.memoryMB {
                Text(verbatim: formatMemory(mem))
                    .font(appSettings.appMonoFont(size: 9, weight: .medium))
                    .foregroundColor(Theme.Liquid.badgeText)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Theme.Liquid.badgeBackground))
                    .fixedSize()
            }

            // CPU badge
            if let cpu = port.cpuUsage {
                Text(verbatim: String(format: "%.1f%%", cpu))
                    .font(appSettings.appMonoFont(size: 9, weight: .bold))
                    .foregroundColor(cpu > 0.5 ? .white : Theme.Liquid.badgeText)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(cpu > 0.5 ? cpuHeatColor(cpu) : Theme.Liquid.badgeBackground))
                    .fixedSize()
            }

            // Actions on hover
            if isHovered {
                HStack(spacing: 4) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.Liquid.accentPurple)
                    }
                    .buttonStyle(PointerButtonStyle())

                    Button(action: onKill) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.Action.kill)
                    }
                    .buttonStyle(PointerButtonStyle())
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isHovered ? Theme.Surface.hover : .clear))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeInOut(duration: 0.15)) { isHovered = h } }
    }
}

// MARK: - Process Group Section (expandable, shows ports)

private struct LiquidProcessSection: View {
    let title: String
    let icon: String
    let groups: [(process: String, ports: [PortProcess], pid: Int)]
    let totalCount: Int
    @ObservedObject var viewModel: PortViewModel
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var isExpanded = true
    @State private var expandedProcesses: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.Liquid.accentPurple)
                    Text(title)
                        .font(appSettings.appFont(size: 13, weight: .semibold))
                        .foregroundColor(Theme.Liquid.headerText)
                    Text(verbatim: "\(totalCount)")
                        .font(appSettings.appMonoFont(size: 11, weight: .bold))
                        .foregroundColor(Theme.Liquid.subtitleText)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.Liquid.badgeBackground))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.Liquid.subtitleText.opacity(0.5))
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(PointerButtonStyle())

            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(groups, id: \.process) { group in
                        processGroupRow(group)
                    }
                }
                .padding(.horizontal, 6).padding(.bottom, 8)
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.Liquid.sectionBackground))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.Liquid.cardBorder, lineWidth: 0.5))
    }

    @ViewBuilder
    private func processGroupRow(_ group: (process: String, ports: [PortProcess], pid: Int)) -> some View {
        let expanded = expandedProcesses.contains(group.process)

        VStack(spacing: 0) {
            // Process header row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expanded { expandedProcesses.remove(group.process) }
                    else { expandedProcesses.insert(group.process) }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Theme.Liquid.subtitleText.opacity(0.5))
                        .frame(width: 10)

                    Text(group.process)
                        .font(appSettings.appFont(size: 12, weight: .medium))
                        .foregroundColor(Theme.Liquid.headerText)
                        .lineLimit(1)

                    Spacer()

                    Text(verbatim: "\(group.ports.count) port\(group.ports.count == 1 ? "" : "s")")
                        .font(appSettings.appFont(size: 11))
                        .foregroundColor(Theme.Liquid.subtitleText)

                    Text(verbatim: "PID \(group.pid)")
                        .font(appSettings.appMonoFont(size: 10))
                        .foregroundColor(Theme.Liquid.subtitleText.opacity(0.6))
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(PointerButtonStyle())

            // Expanded: show individual ports
            if expanded {
                ForEach(group.ports, id: \.id) { port in
                    LiquidPortRow(
                        port: port,
                        onKill: { viewModel.killPort(port.port) },
                        onCopy: { viewModel.copyPortInfo(port) }
                    )
                    .padding(.leading, 16)
                }
            }
        }
    }
}

// MARK: - Connection Type Section (Local/Database/K8s/etc.)

private struct LiquidConnectionTypeSection: View {
    let type: ConnectionType
    let ports: [PortProcess]
    @ObservedObject var viewModel: PortViewModel
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: type.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(type.color)
                    Text(type.rawValue)
                        .font(appSettings.appFont(size: 13, weight: .semibold))
                        .foregroundColor(Theme.Liquid.headerText)
                    Text(verbatim: "\(ports.count)")
                        .font(appSettings.appMonoFont(size: 11, weight: .bold))
                        .foregroundColor(Theme.Liquid.subtitleText)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.Liquid.badgeBackground))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.Liquid.subtitleText.opacity(0.5))
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(PointerButtonStyle())

            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(ports, id: \.id) { port in
                        LiquidPortRow(
                            port: port,
                            onKill: { viewModel.killPort(port.port) },
                            onCopy: { viewModel.copyPortInfo(port) }
                        )
                    }
                }
                .padding(.horizontal, 4).padding(.bottom, 8)
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.Liquid.sectionBackground))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.Liquid.cardBorder, lineWidth: 0.5))
    }
}

// MARK: - Schedules Section

private struct LiquidSchedulesSection: View {
    let cronjobs: [CronjobEntry]
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.Liquid.accentPurple)
                    Text("Schedules")
                        .font(appSettings.appFont(size: 13, weight: .semibold))
                        .foregroundColor(Theme.Liquid.headerText)
                    Text(verbatim: "\(cronjobs.count)")
                        .font(appSettings.appMonoFont(size: 11, weight: .bold))
                        .foregroundColor(Theme.Liquid.subtitleText)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.Liquid.badgeBackground))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.Liquid.subtitleText.opacity(0.5))
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(PointerButtonStyle())

            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(cronjobs) { job in
                        LiquidCronjobRow(cronjob: job)
                    }
                }
                .padding(.horizontal, 6).padding(.bottom, 8)
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.Liquid.sectionBackground))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.Liquid.cardBorder, lineWidth: 0.5))
    }
}

private struct LiquidCronjobRow: View {
    let cronjob: CronjobEntry
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var isHovered = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    private var sourceColor: Color {
        cronjob.source == "user" ? Theme.Classification.userApp : Theme.Classification.system
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(cronjob.scheduleHuman ?? cronjob.schedule)
                        .font(appSettings.appFont(size: 12, weight: .medium))
                        .foregroundColor(Theme.Status.warning)
                        .lineLimit(1)

                    if let user = cronjob.user {
                        Text(user)
                            .font(appSettings.appFont(size: 9, weight: .medium))
                            .foregroundColor(Theme.Liquid.accentPurple)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Theme.Liquid.accentPurpleMuted)
                            .cornerRadius(3)
                    }

                    // Source badge
                    Text(cronjob.source == "user" ? "user" : "sys")
                        .font(appSettings.appFont(size: 8, weight: .bold))
                        .foregroundColor(sourceColor)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(sourceColor.opacity(0.15))
                        .cornerRadius(3)
                }

                Text(cronjob.command)
                    .font(appSettings.appMonoFont(size: 10))
                    .foregroundColor(Theme.Liquid.subtitleText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if let nextRun = cronjob.nextRun {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Next")
                        .font(appSettings.appFont(size: 8))
                        .foregroundColor(Theme.Liquid.subtitleText)
                    Text(Self.dateFormatter.string(from: nextRun))
                        .font(appSettings.appMonoFont(size: 10, weight: .medium))
                        .foregroundColor(Theme.Liquid.accentPurple)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(isHovered ? Theme.Surface.hover : .clear))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeInOut(duration: 0.12)) { isHovered = h } }
    }
}

// MARK: - Connection Section (kept for compatibility)

struct MenuBarConnectionSection: View {
    let processName: String
    let connections: [EstablishedConnection]
    let totalCount: Int
    let onKill: (Int) -> Void

    @ObservedObject private var appSettings = AppSettings.shared
    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 2) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "network").font(.system(size: 11)).foregroundColor(Theme.Action.treeView)
                    Text(processName).font(appSettings.appFont(size: appSettings.fontSize - 1, weight: .semibold))
                    Text(verbatim: "\(totalCount)").font(appSettings.appMonoFont(size: appSettings.fontSize - 2, weight: .medium)).foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .medium)).foregroundColor(.secondary.opacity(0.6))
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
            }
            .buttonStyle(PointerButtonStyle())
            if isExpanded {
                ForEach(connections, id: \.id) { conn in
                    MenuBarConnectionRow(connection: conn, onKill: { onKill(conn.pid) })
                }
            }
        }
    }
}

struct MenuBarConnectionRow: View {
    let connection: EstablishedConnection
    let onKill: () -> Void

    @ObservedObject private var appSettings = AppSettings.shared
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(connection.isBlocklisted ? Theme.Action.kill : Theme.Status.connected).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(connection.remoteAddress)
                        .font(appSettings.appMonoFont(size: appSettings.fontSize, weight: connection.isBlocklisted ? .bold : .medium))
                        .foregroundColor(connection.isBlocklisted ? Theme.Action.kill : .primary)
                        .lineLimit(1).truncationMode(.middle)
                    Text(connection.state)
                        .font(appSettings.appMonoFont(size: max(appSettings.fontSize - 3, 8), weight: .medium))
                        .foregroundColor(.secondary).padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Theme.Surface.headerTint).cornerRadius(3)
                }
                Text(verbatim: "PID \(connection.pid)")
                    .font(appSettings.appMonoFont(size: appSettings.fontSize - 2, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isHovered {
                Button(action: onKill) {
                    Text("Kill").font(appSettings.appFont(size: 9, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(Theme.Action.kill).cornerRadius(10)
                }
                .buttonStyle(PointerButtonStyle()).transition(.opacity)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(isHovered ? Theme.Surface.hover : .clear).cornerRadius(4)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeInOut(duration: 0.18)) { isHovered = h } }
    }
}
