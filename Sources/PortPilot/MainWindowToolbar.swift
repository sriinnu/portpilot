import SwiftUI

private let toolbarSelectionSpring = Animation.spring(response: 0.28, dampingFraction: 0.82, blendDuration: 0.12)

// MARK: - Main Window Toolbar
struct MainWindowToolbar: View {
    @Binding var searchText: String
    @ObservedObject var viewModel: PortViewModel
    let onRefresh: () -> Void
    let onSettings: () -> Void
    let isLoading: Bool
    let portCount: Int
    let totalCount: Int
    @Binding var selectedMainTab: MainTab

    var body: some View {
        VStack(spacing: 0) {
            // Top row: refresh, count, search, settings
            HStack(spacing: 10) {
                Button(action: onRefresh) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: Theme.Icon.refresh)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.Action.refresh)
                    }
                }
                .buttonStyle(.borderless)
                .help("Refresh (\u{2318}R)")

                if selectedMainTab == .ports {
                    ToolbarPortSummary(portCount: portCount, totalCount: totalCount)
                } else {
                    Text("Schedules")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Spacer()

                // Search field
                HStack(spacing: 6) {
                    Image(systemName: Theme.Icon.search)
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    TextField(selectedMainTab == .ports ? "Search ports, processes..." : "Search cronjobs...", text: $searchText)
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
                .padding(.vertical, 6)
                .background(Theme.Surface.chromeTint)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Size.cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Size.cornerRadius, style: .continuous))
                .frame(maxWidth: 280)

                Button(action: onSettings) {
                    Image(systemName: Theme.Icon.settings)
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                .help("Settings (\u{2318},)")
            }
            .padding(.horizontal, Theme.Spacing.sectionInset)
            .padding(.vertical, Theme.Spacing.sm)

            // Main tabs row (Ports / Schedules)
            HStack(spacing: 8) {
                MainTabPill(
                    label: "Ports",
                    icon: "network",
                    isSelected: selectedMainTab == .ports
                ) {
                    withAnimation(toolbarSelectionSpring) {
                        selectedMainTab = .ports
                    }
                }

                MainTabPill(
                    label: "Schedules",
                    icon: "clock",
                    isSelected: selectedMainTab == .schedules
                ) {
                    withAnimation(toolbarSelectionSpring) {
                        selectedMainTab = .schedules
                    }
                }

                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.sectionInset)
            .padding(.bottom, Theme.Spacing.xs)

            // Source tabs row (only visible for Ports tab)
            if selectedMainTab == .ports {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PortSourceFilter.allCases) { source in
                            SourceTabPill(
                                source: source,
                                count: viewModel.sourceCounts[source] ?? 0,
                                isSelected: viewModel.selectedSourceFilter == source
                            ) {
                                withAnimation(toolbarSelectionSpring) {
                                    viewModel.selectedSourceFilter = viewModel.selectedSourceFilter == source ? .all : source
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Theme.Surface.headerTint)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                }
                .padding(.horizontal, Theme.Spacing.sectionInset)
                .padding(.bottom, Theme.Spacing.xs)

                // Filter pills row
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        // Protocol filters
                        ProtocolPill(label: "TCP", isSelected: viewModel.selectedProtocol == .tcp) {
                            withAnimation(toolbarSelectionSpring) {
                                viewModel.selectedProtocol = viewModel.selectedProtocol == .tcp ? .all : .tcp
                            }
                        }
                        ProtocolPill(label: "UDP", isSelected: viewModel.selectedProtocol == .udp) {
                            withAnimation(toolbarSelectionSpring) {
                                viewModel.selectedProtocol = viewModel.selectedProtocol == .udp ? .all : .udp
                            }
                        }

                        DividerPill()

                        // Category filters
                        ForEach(FilterCategory.allCases) { cat in
                            CategoryPill(
                                category: cat,
                                count: viewModel.categoryCounts[cat] ?? 0,
                                isSelected: viewModel.selectedCategory == cat
                            ) {
                                withAnimation(toolbarSelectionSpring) {
                                    viewModel.selectedCategory = viewModel.selectedCategory == cat ? .all : cat
                                }
                            }
                        }

                        DividerPill()

                        // Hide system toggle
                        TogglePill(
                            label: "Hide System",
                            icon: viewModel.hideSystemProcesses ? "eye.slash" : "eye",
                            isActive: viewModel.hideSystemProcesses
                        ) {
                            withAnimation(toolbarSelectionSpring) {
                                viewModel.hideSystemProcesses.toggle()
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal, Theme.Spacing.sectionInset)
                    .padding(.vertical, Theme.Spacing.sm)
                }
            }
        }
        .background(Theme.Surface.windowBackground)
    }
}

// MARK: - Main Tab Pill
struct MainTabPill: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(isSelected ? .white : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? Theme.Badge.accentBackground
                    : Theme.Surface.chromeTint
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Size.cornerRadiusLarge, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.white.opacity(0.16) : Color.primary.opacity(0.06),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Size.cornerRadiusLarge, style: .continuous))
            .animation(toolbarSelectionSpring, value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

struct ToolbarPortSummary: View {
    let portCount: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: Theme.Icon.portsTab)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            Text("\(portCount)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)

            Text(portCount == totalCount ? "active" : "shown")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            if portCount != totalCount {
                Text("of \(totalCount)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary.opacity(Theme.Opacity.subtle))
            }
        }
    }
}

struct SourceTabPill: View {
    let source: PortSourceFilter
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: source.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(source.shortLabel)
                    .font(.system(size: 12, weight: .semibold))
                if isSelected || source == .all {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(isSelected ? .white.opacity(Theme.Opacity.subtle) : .secondary.opacity(Theme.Opacity.secondary))
                }
            }
            .foregroundColor(isSelected ? .white : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                isSelected
                    ? source.color
                    : Theme.Surface.chromeTint
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.white.opacity(0.16) : Color.primary.opacity(0.06),
                        lineWidth: 1
                    )
            )
            .cornerRadius(13)
            .animation(toolbarSelectionSpring, value: isSelected)
        }
        .buttonStyle(.plain)
        .help(source.rawValue)
    }
}

struct ProtocolPill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    isSelected
                        ? Theme.Badge.accentBackground
                        : Theme.Surface.chromeTint
                )
                .cornerRadius(11)
        }
        .buttonStyle(.plain)
    }
}

struct CategoryPill: View {
    let category: FilterCategory
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    private var pillColor: Color {
        switch category {
        case .all: return Theme.Badge.accentBackground
        case .web: return Theme.Section.local
        case .database: return Theme.Section.database
        case .dev: return Theme.Section.kubernetes
        case .system: return Theme.Classification.system
        case .favorites: return Color.yellow
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: category.icon)
                    .font(.system(size: 10))
                Text(category.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                if count > 0 && category != .all && isSelected {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(isSelected ? .white.opacity(Theme.Opacity.subtle) : .secondary.opacity(Theme.Opacity.secondary))
                }
            }
            .foregroundColor(isSelected ? .white : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isSelected
                    ? pillColor
                    : Theme.Surface.chromeTint
            )
            .cornerRadius(11)
        }
        .buttonStyle(.plain)
    }
}

struct TogglePill: View {
    let label: String
    let icon: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(isActive ? .white : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isActive
                    ? Theme.Section.ssh
                    : Theme.Surface.chromeTint
            )
            .cornerRadius(11)
        }
        .buttonStyle(.plain)
    }
}

struct DividerPill: View {
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(Theme.Opacity.disabled))
            .frame(width: 1, height: 18)
    }
}

// MARK: - Main Window Live Traffic Strip (Liquid Glass Control Deck)
// I mirror the menubar's strip but stretched to the main-window width: five
// tiles including throughput, each with a tall sparkline.
struct MainTrafficStrip: View {
    @ObservedObject var viewModel: PortViewModel
    @ObservedObject var metrics: LiveMetricsHistory
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        HStack(spacing: 10) {
            tile(
                label: "Active Ports",
                value: "\(viewModel.filteredPorts.count)",
                history: metrics.active,
                dotColor: Theme.Alert.dotActive,
                pulse: true
            )
            tile(
                label: "Sockets",
                value: "\(viewModel.ports.filter { $0.isUnixSocket }.count)",
                history: metrics.sockets,
                accent: Theme.Action.treeView
            )
            tile(
                label: "Connections",
                value: "\(viewModel.allConnections.count)",
                history: metrics.connections,
                accent: Theme.Section.kubernetes
            )
            tile(
                label: "CPU Load",
                value: String(format: "%.0f%%", metrics.cpu.last ?? 0),
                history: metrics.cpu,
                accent: Theme.Status.warning
            )
            tile(
                label: "Total Tracked",
                value: "\(viewModel.totalCount)",
                history: metrics.active,
                accent: Theme.Section.ssh,
                muted: true
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.Surface.groupedFill)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Surface.groupedStroke)
                .frame(height: 0.5)
        }
    }

    private func tile(label: String, value: String, history: [Double], accent: Color? = nil, dotColor: Color = Theme.Alert.dotActive, pulse: Bool = false, muted: Bool = false) -> some View {
        let stroke = accent ?? Theme.Liquid.sparklineStroke
        let fill = (accent ?? Theme.Liquid.sparklineStroke).opacity(muted ? 0.1 : 0.22)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if pulse {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: dotColor.opacity(0.6), radius: 2)
                }
                Text(label)
                    .font(appSettings.appFont(size: 9, weight: .semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(appSettings.appMonoFont(size: 20, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Sparkline(values: history, stroke: stroke, fill: fill, lineWidth: 1.2)
                .frame(height: 22)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Surface.controlBackground.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.Surface.groupedStroke, lineWidth: 0.5)
        )
    }
}

// MARK: - Inspector Tab Bar
// Pills above the right-hand configuration panel — Overview / Metrics / Logs.
enum InspectorTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case metrics = "Metrics"
    case logs = "Logs"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: return "doc.text.magnifyingglass"
        case .metrics: return "waveform.path.ecg"
        case .logs: return "text.alignleft"
        }
    }
}

struct InspectorTabBar: View {
    @Binding var selection: InspectorTab
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        HStack(spacing: 6) {
            ForEach(InspectorTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) { selection = tab }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(tab.rawValue)
                            .font(appSettings.appFont(size: 11, weight: .semibold))
                    }
                    .foregroundColor(selection == tab ? .white : .secondary)
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selection == tab ? Theme.Liquid.accentPurple : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.Surface.headerTint)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Surface.groupedStroke).frame(height: 0.5)
        }
    }
}

// MARK: - Inspector Metrics Pane
// Concept 5/9 style: big, calm sparklines showing CPU + memory history for
// the selected port. When no port is selected, I show a quiet empty state.
struct InspectorMetricsPane: View {
    let port: PortProcess?
    @ObservedObject var metrics: LiveMetricsHistory
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let port = port {
                    header(for: port)
                    cpuCard(for: port)
                    memoryCard(for: port)
                    snapshotCard(for: port)
                } else {
                    emptyState
                }
            }
            .padding(16)
        }
    }

    private func header(for port: PortProcess) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.Status.connected)
                .frame(width: 10, height: 10)
                .shadow(color: Theme.Status.connected.opacity(0.5), radius: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: port.isUnixSocket ? "PID \(port.pid)" : ":\(port.port)")
                    .font(appSettings.appMonoFont(size: 22, weight: .bold))
                Text(port.command)
                    .font(appSettings.appFont(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(port.protocolName.uppercased())
                .font(appSettings.appMonoFont(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.Surface.groupedFill)
                )
        }
    }

    private func cpuCard(for port: PortProcess) -> some View {
        let history = metrics.history(for: port)
        let latest = history.last ?? (port.cpuUsage ?? 0)
        return metricCard(
            title: "CPU",
            valueText: String(format: "%.1f%%", latest),
            helper: "last \(history.count * 2)s",
            history: history,
            stroke: Theme.Status.warning,
            fill: Theme.Status.warning.opacity(0.2)
        )
    }

    private func memoryCard(for port: PortProcess) -> some View {
        let latest = port.memoryMB ?? 0
        // Memory history is not sampled per-port today, so I render a flat
        // baseline. The card layout stays consistent for when we wire it up.
        return metricCard(
            title: "Memory",
            valueText: formatMemory(latest),
            helper: "current snapshot",
            history: [],
            stroke: Theme.Action.treeView,
            fill: Theme.Action.treeView.opacity(0.18)
        )
    }

    private func snapshotCard(for port: PortProcess) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Snapshot")
                .font(appSettings.appFont(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
            snapshotRow("PID", "\(port.pid)")
            snapshotRow("User", port.user)
            if let parent = port.parentPID { snapshotRow("PPID", "\(parent)") }
            if let started = port.startTime {
                snapshotRow("Started", Self.uptimeFormatter.localizedString(for: started, relativeTo: Date()))
            }
            if let cwd = port.workingDirectory, !cwd.isEmpty {
                snapshotRow("CWD", cwd)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Surface.groupedFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.Surface.groupedStroke, lineWidth: 0.5)
        )
    }

    private func snapshotRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(appSettings.appFont(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(appSettings.appMonoFont(size: 11))
                .foregroundColor(.primary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private func metricCard(title: String, valueText: String, helper: String, history: [Double], stroke: Color, fill: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(appSettings.appFont(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer()
                Text(helper)
                    .font(appSettings.appFont(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            Text(valueText)
                .font(appSettings.appMonoFont(size: 28, weight: .bold))
            Sparkline(values: history, stroke: stroke, fill: fill, lineWidth: 1.4)
                .frame(height: 52)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Surface.groupedFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.Surface.groupedStroke, lineWidth: 0.5)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.secondary.opacity(0.6))
            Text("Select a port")
                .font(appSettings.appFont(size: 14, weight: .semibold))
            Text("Live CPU and memory metrics will appear here.")
                .font(appSettings.appFont(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private func formatMemory(_ mb: Double) -> String {
        if mb >= 1024 { return String(format: "%.2f GB", mb / 1024.0) }
        if mb >= 10 { return String(format: "%.0f MB", mb) }
        return String(format: "%.1f MB", mb)
    }

    private static let uptimeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

// MARK: - Main Status Bar
// Footer strip — a quiet signal of health at a glance, mirroring concept 12's
// "System Health: All Systems Nominal" language.
struct MainStatusBar: View {
    @ObservedObject var viewModel: PortViewModel
    @ObservedObject private var appSettings = AppSettings.shared

    private var healthTint: Color {
        switch viewModel.alertState {
        case .normal: return Theme.Status.connected
        case .warning: return Theme.Status.warning
        case .critical: return Theme.Action.kill
        }
    }

    private var healthLabel: String {
        switch viewModel.alertState {
        case .normal: return "All systems nominal"
        case .warning: return "Elevated activity"
        case .critical: return "Critical connections"
        }
    }

    private var lastRefreshText: String {
        guard let last = viewModel.lastRefresh else { return "—" }
        return Self.formatter.string(from: last)
    }

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Circle()
                    .fill(healthTint)
                    .frame(width: 7, height: 7)
                    .shadow(color: healthTint.opacity(0.55), radius: 2)
                Text(healthLabel)
                    .font(appSettings.appFont(size: 11, weight: .semibold))
            }
            divider
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("Last refresh")
                    .font(appSettings.appFont(size: 10))
                    .foregroundColor(.secondary)
                Text(lastRefreshText)
                    .font(appSettings.appMonoFont(size: 10, weight: .medium))
            }
            divider
            HStack(spacing: 4) {
                Image(systemName: "network")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(verbatim: "\(viewModel.portCount) shown / \(viewModel.totalCount) tracked")
                    .font(appSettings.appMonoFont(size: 10, weight: .medium))
                    .foregroundColor(.primary.opacity(0.85))
            }
            Spacer()
            Text("PortPilot \u{2022} Liquid Glass Control Deck")
                .font(appSettings.appFont(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Theme.Surface.chromeTint)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Surface.groupedStroke).frame(height: 0.5)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 1, height: 12)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
