import SwiftUI

private let liquidSpring = Animation.spring(response: 0.26, dampingFraction: 0.84, blendDuration: 0.1)

// MARK: - Protocol Filter
enum MenuBarProtocolFilter: String, CaseIterable {
    case all = "All"
    case tcp = "TCP"
    case udp = "UDP"
}

// AlertState, LiveMetricsHistory, Sparkline, LiveTrafficStrip, and
// PointerButtonStyle now live under Sources/PortPilot/Liquid/ as modular
// reusable components shared with the main window.

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

    /// How the tree view nests rows: by process name, or by owning project
    /// (git repo, falling back to cwd, then process).
    private enum TreeGrouping {
        case process
        case project
    }
    @State private var treeGrouping: TreeGrouping = .process
    @State private var showMoreMenu = false
    @State private var confirmingKillAll = false
    @StateObject private var metrics = LiveMetricsHistory()

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
            if let error = viewModel.errorMessage {
                errorBanner(error)
            }
            liveTrafficView
            searchView
            filterView
            separatorView
            scrollContent
            footerView
        }
        .frame(width: Theme.Liquid.panelWidth)
        // Paper strata on diorama themes; flat themes keep the panel's
        // translucent material untouched. Cards above sit on it like cut
        // paper sheets.
        .background {
            if let strata = Theme.Surface.strata { strata }
        }
        .overlay {
            if showMoreMenu {
                Color.black.opacity(0.001)
                    .onTapGesture { showMoreMenu = false }
            }
        }
        .overlay(alignment: .topTrailing) { moreMenuView }
        .animation(.easeOut(duration: 0.15), value: showMoreMenu)
        .onAppear { metrics.start(viewModel: viewModel) }
        .onDisappear { metrics.stop() }
        // Errors raised while this dropdown is the visible surface show here
        // as a banner. The model owns the 4s auto-consume (see raiseError) —
        // the banner just renders; dismissal goes through dismissError().
        .animation(.easeOut(duration: 0.2), value: viewModel.errorMessage)
        // ⌘T from the panel's key monitor — the footer glyph is real now.
        .onReceive(NotificationCenter.default.publisher(for: .toggleDropdownTreeView)) { _ in
            withAnimation(liquidSpring) { showTreeView.toggle() }
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.Status.error)
            Text(message)
                .font(appSettings.appFont(size: 11))
                .foregroundColor(.primary)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button {
                viewModel.dismissError()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.Liquid.subtitleText)
            }
            .buttonStyle(PointerButtonStyle())
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.Status.error.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.Status.error.opacity(0.25), lineWidth: 0.5))
        .padding(.horizontal, 14).padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }

    // MARK: - Live Traffic Strip (replaces the flat stats line)

    private var liveTrafficView: some View {
        LiveTrafficStrip(
            active: filteredPorts.count,
            sockets: socketCount,
            connections: viewModel.allConnections.count,
            cpu: filteredPorts.reduce(0.0) { $0 + ($1.cpuUsage ?? 0) },
            activeHistory: metrics.active,
            socketsHistory: metrics.sockets,
            connectionsHistory: metrics.connections,
            cpuHistory: metrics.cpu,
            alertState: alertState
        )
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
                headerBtn(icon: "arrow.clockwise", label: "Refresh") {
                    viewModel.refreshPorts()
                    viewModel.refreshAllConnections()
                }
                headerBtn(icon: "gearshape", label: "Settings") {
                    onDismiss()
                    onOpenSettings()
                }
                headerBtn(icon: "ellipsis", label: "More") {
                    showMoreMenu.toggle()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private func headerBtn(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.Liquid.subtitleText)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(PointerButtonStyle())
        .accessibilityLabel(label)
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
                .accessibilityLabel("Clear search")
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
                        onKill: { viewModel.killPort(port) },
                        onPauseResume: {
                            if port.isStopped { viewModel.resumeProcess(port) } else { viewModel.pauseProcess(port) }
                        },
                        onCopy: { viewModel.copyPortInfo(port) },
                        history: metrics.history(for: port)
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
                    viewModel: viewModel,
                    metrics: metrics
                )
            }
        }
    }

    // MARK: Process Groups (Tree View)

    /// Group by owning project: the git repo when enrichment found one,
    /// else the working directory's last component, else the process name.
    /// Repo groups sort first so real projects lead the tree.
    private var projectGroups: [(process: String, ports: [PortProcess], pid: Int)] {
        struct Key: Hashable { let name: String; let isRepo: Bool }

        let dict = Dictionary(grouping: filteredPorts) { port -> Key in
            if let repo = port.gitRepo, !repo.isEmpty {
                return Key(name: repo, isRepo: true)
            }
            if let cwd = port.workingDirectory, !cwd.isEmpty {
                return Key(name: (cwd as NSString).lastPathComponent, isRepo: false)
            }
            return Key(name: port.command, isRepo: false)
        }

        return dict
            .sorted {
                if $0.key.isRepo != $1.key.isRepo { return $0.key.isRepo }
                return $0.value.count > $1.value.count
            }
            .map { (process: $0.key.name, ports: $0.value, pid: $0.value.first?.pid ?? 0) }
    }

    private var processGroupsSection: some View {
        let groups: [(process: String, ports: [PortProcess], pid: Int)]
        let title: String
        let icon: String
        switch treeGrouping {
        case .process:
            groups = processGroups
            title = "Local Processes"
            icon = "folder.fill"
        case .project:
            groups = projectGroups
            title = "Projects"
            icon = "square.stack.3d.up.fill"
        }

        return VStack(spacing: 8) {
            groupingToggle
            if !groups.isEmpty {
                LiquidProcessSection(
                    title: title,
                    icon: icon,
                    groups: groups,
                    totalCount: filteredPorts.count,
                    showsPID: treeGrouping == .process,
                    viewModel: viewModel,
                    metrics: metrics
                )
            }
        }
    }

    /// Process/Project axis chips — only meaningful in tree view.
    private var groupingToggle: some View {
        HStack(spacing: 4) {
            groupingChip("Process", systemImage: "cpu", selection: .process)
            groupingChip("Project", systemImage: "square.stack.3d.up", selection: .project)
            Spacer()
        }
    }

    private func groupingChip(_ label: String, systemImage: String, selection: TreeGrouping) -> some View {
        let selected = treeGrouping == selection
        return Button {
            withAnimation(liquidSpring) { treeGrouping = selection }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 9, weight: .semibold))
                Text(label).font(appSettings.appFont(size: 11, weight: .medium))
            }
            .foregroundColor(selected ? .white : Theme.Liquid.subtitleText)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Theme.Liquid.accentPurple : Theme.Liquid.badgeBackground)
            )
        }
        .buttonStyle(PointerButtonStyle())
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
            // One condition for icon, color, and both labels — the icon used
            // to say "filtered" while the color still said "all clear".
            let unfiltered = searchText.isEmpty && protocolFilter == .all && sourceFilter == .all
            VStack(spacing: 10) {
                Image(systemName: unfiltered ? "checkmark.circle" : "magnifyingglass")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(unfiltered ? Theme.Alert.dotActive : Theme.Liquid.subtitleText)
                Text(unfiltered ? "No Active Ports" : "No matching ports")
                    .font(appSettings.appFont(size: 14, weight: .medium))
                    .foregroundColor(Theme.Liquid.headerText)
                Text(unfiltered ? "All ports are available" : "Try a different search or filter")
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
                moreItem("Refresh", icon: "arrow.clockwise") {
                    showMoreMenu = false
                    viewModel.refreshPorts()
                    viewModel.refreshAllConnections()
                }
                // Kill what the dropdown is SHOWING (search-filtered), network
                // ports only — "Kill All" on the raw list used to sweep in
                // every Unix-socket holder regardless of the filter.
                let killAllTargets = filteredPorts.filter { !$0.isUnixSocket }
                if !killAllTargets.isEmpty {
                    moreItem(confirmingKillAll ? "Confirm Kill All? (\(killAllTargets.count))" : "Kill All...", icon: confirmingKillAll ? "exclamationmark.triangle.fill" : "xmark.circle", tint: Theme.Action.kill) {
                        if confirmingKillAll {
                            confirmingKillAll = false
                            showMoreMenu = false
                            viewModel.killSelectedPorts(Set(killAllTargets))
                        } else {
                            confirmingKillAll = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { confirmingKillAll = false }
                        }
                    }
                }
                Divider().padding(.horizontal, 8).padding(.vertical, 2)
                moreItem("Settings", icon: "gearshape") {
                    showMoreMenu = false; onDismiss(); onOpenSettings()
                }
                Divider().padding(.horizontal, 8).padding(.vertical, 2)
                moreItem("Quit", icon: "power") { showMoreMenu = false; onQuit() }
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

    private func moreItem(_ label: String, icon: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        // No ⌘-shortcut glyphs: this is a custom panel, not an NSMenu — it
        // has no key-equivalent handling, so the hints were decorative lies.
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12, weight: .medium))
                    .foregroundColor(tint ?? Theme.Liquid.subtitleText).frame(width: 16)
                Text(label).font(appSettings.appFont(size: 13)).foregroundColor(tint ?? Theme.Liquid.headerText)
                Spacer()
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
    let onPauseResume: () -> Void
    let onCopy: () -> Void
    var history: [Double] = []
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var isHovered = false

    private var portStr: String { ":\(port.port)" }
    private var pidStr: String { "PID \(port.pid)" }

    var body: some View {
        HStack(spacing: 6) {
            // Status dot — warning tone while the process is frozen
            Circle()
                .fill(port.isStopped ? Theme.Alert.dotWarning : Theme.Alert.dotActive)
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

            // Inline activity trace — a quiet pulse of the row's recent CPU.
            if history.count >= 2 {
                Sparkline(
                    values: history,
                    stroke: Theme.Liquid.rowSparkline,
                    fill: Theme.Liquid.rowSparkline.opacity(0.18),
                    lineWidth: 1.0,
                    showDot: false
                )
                .frame(width: 36, height: 12)
                .opacity(isHovered ? 0.4 : 1.0)
            }

            // PID — verbatim
            Text(verbatim: pidStr)
                .font(appSettings.appMonoFont(size: 9))
                .foregroundColor(Theme.Liquid.subtitleText.opacity(0.6))
                .fixedSize()

            // Memory badge
            if let mem = port.memoryMB {
                Text(verbatim: formatMemorySpacious(mem))
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

            // Actions — visually hover-revealed, but always in the hierarchy:
            // `if isHovered` made them invisible to VoiceOver (which never
            // hovers), so keyboard/VO users had no kill or copy at all here.
            HStack(spacing: 4) {
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.Liquid.accentPurple)
                }
                .buttonStyle(PointerButtonStyle())
                .accessibilityLabel("Copy port info")

                Button(action: onPauseResume) {
                    Image(systemName: port.isStopped ? "play.circle" : "pause.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(port.isStopped ? Theme.Status.connected : Theme.Status.warning)
                }
                .buttonStyle(PointerButtonStyle())
                .help(port.isStopped ? "Resume (SIGCONT)" : "Pause (SIGSTOP) — port stays bound")
                .accessibilityLabel(port.isStopped ? "Resume process \(port.command)" : "Pause process \(port.command)")

                Button(action: onKill) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.Action.kill)
                }
                .buttonStyle(PointerButtonStyle())
                .accessibilityLabel("Kill process \(port.command), pid \(port.pid)")
            }
            .opacity(isHovered ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
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
    /// Project groups mix many pids — a "PID n" there would be a lie.
    var showsPID: Bool = true
    @ObservedObject var viewModel: PortViewModel
    @ObservedObject var metrics: LiveMetricsHistory
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

                    if showsPID {
                        Text(verbatim: "PID \(group.pid)")
                            .font(appSettings.appMonoFont(size: 10))
                            .foregroundColor(Theme.Liquid.subtitleText.opacity(0.6))
                    }
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
                        onKill: { viewModel.killPort(port) },
                        onPauseResume: {
                            if port.isStopped { viewModel.resumeProcess(port) } else { viewModel.pauseProcess(port) }
                        },
                        onCopy: { viewModel.copyPortInfo(port) },
                        history: metrics.history(for: port)
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
    @ObservedObject var metrics: LiveMetricsHistory
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
                            onKill: { viewModel.killPort(port) },
                            onPauseResume: {
                                if port.isStopped { viewModel.resumeProcess(port) } else { viewModel.pauseProcess(port) }
                            },
                            onCopy: { viewModel.copyPortInfo(port) },
                            history: metrics.history(for: port)
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

            if cronjob.isPaused {
                Text("Paused")
                    .font(appSettings.appFont(size: 9, weight: .medium))
                    .foregroundColor(Theme.Liquid.subtitleText)
            } else if let nextRun = cronjob.nextRun {
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
        .opacity(cronjob.isPaused ? 0.55 : 1.0)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(isHovered ? Theme.Surface.hover : .clear))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeInOut(duration: 0.12)) { isHovered = h } }
    }
}
