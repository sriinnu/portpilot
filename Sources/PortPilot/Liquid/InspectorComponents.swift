import SwiftUI

// MARK: - Inspector Tab

/// The three panes available in the right-hand inspector column.
///
/// I back this with a plain string raw value so the case name is also the
/// tab label, and each case carries its own SF Symbol for the pill bar.
enum InspectorTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case metrics = "Metrics"
    case logs = "Logs"

    /// Stable identity for SwiftUI iteration — the raw label doubles as id.
    var id: String { rawValue }

    /// SF Symbol name I render alongside the tab's label in the pill bar.
    var icon: String {
        switch self {
        case .overview: return "doc.text.magnifyingglass"
        case .metrics: return "waveform.path.ecg"
        case .logs: return "text.alignleft"
        }
    }
}

// MARK: - Inspector Tab Bar

/// Pill-style tab bar rendered above the right-hand inspector column.
///
/// I animate selection with a small spring so the purple pill slides into
/// its new position rather than snapping — matches the Liquid motion cues
/// used elsewhere in the chrome.
struct InspectorTabBar: View {
    /// Two-way binding to the currently selected inspector pane.
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

/// The Metrics tab's content: CPU sparkline card, memory card, process
/// identity snapshot, and an inline connections table for the selected port.
///
/// When nothing is selected I render a quiet empty state instead of zero
/// cards — keeps the column from feeling broken before the user clicks in.
struct InspectorMetricsPane: View {
    /// Selected port to inspect, or `nil` when nothing is picked.
    let port: PortProcess?
    /// Shared sampler I pull per-port CPU history from.
    @ObservedObject var metrics: LiveMetricsHistory
    /// View model I read the connections list from.
    @ObservedObject var viewModel: PortViewModel
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let port = port {
                    header(for: port)
                    cpuCard(for: port)
                    memoryCard(for: port)
                    snapshotCard(for: port)
                    connectionsCard(for: port)
                } else {
                    emptyState
                }
            }
            .padding(16)
        }
    }

    // MARK: Header

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

    // MARK: Cards

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
        // Per-port memory history is not sampled yet. I render a flat baseline
        // so the card layout stays consistent for when we wire it up.
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
            RoundedRectangle(cornerRadius: Theme.Liquid.cardCornerRadius, style: .continuous)
                .fill(Theme.Surface.groupedFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Liquid.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.Surface.groupedStroke, lineWidth: Theme.Liquid.cardStrokeWidth)
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

    // Connections for the selected PID, surfaced inline so you can see what's
    // talking to this process without navigating elsewhere.
    private func connectionsCard(for port: PortProcess) -> some View {
        let conns = viewModel.allConnections.filter { $0.pid == port.pid }.prefix(8)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Connections")
                    .font(appSettings.appFont(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer()
                Text("\(viewModel.allConnections.filter { $0.pid == port.pid }.count) total")
                    .font(appSettings.appFont(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            if conns.isEmpty {
                Text("No established connections")
                    .font(appSettings.appFont(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(conns), id: \.id) { conn in
                        connectionRow(conn)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Liquid.cardCornerRadius, style: .continuous)
                .fill(Theme.Surface.groupedFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Liquid.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.Surface.groupedStroke, lineWidth: Theme.Liquid.cardStrokeWidth)
        )
    }

    private func connectionRow(_ conn: EstablishedConnection) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(conn.isBlocklisted ? Theme.Action.kill : Theme.Status.connected)
                .frame(width: 6, height: 6)
            Text(conn.remoteHostname ?? conn.remoteAddress)
                .font(appSettings.appMonoFont(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(conn.state)
                .font(appSettings.appMonoFont(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.Surface.controlBackground)
                )
        }
    }

    // Generic metric card used by CPU + memory panes.
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
            RoundedRectangle(cornerRadius: Theme.Liquid.cardCornerRadius, style: .continuous)
                .fill(Theme.Surface.groupedFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Liquid.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.Surface.groupedStroke, lineWidth: Theme.Liquid.cardStrokeWidth)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.secondary.opacity(0.6))
            Text("Select a port")
                .font(appSettings.appFont(size: 14, weight: .semibold))
            Text("Live CPU, memory and connection metrics will appear here.")
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
