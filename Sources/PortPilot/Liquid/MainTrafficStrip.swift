import SwiftUI

// MARK: - Main Window Live Traffic Strip

/// The menubar strip scaled up for the main window — five tiles, taller
/// sparklines, and a subtle bottom rule that frames the data section below.
///
/// I derive every tile accent from the Liquid theme so palette changes in
/// `AppSettings` repaint the whole strip without me touching this file.
struct MainTrafficStrip: View {
    /// View model I read current counts and totals from.
    @ObservedObject var viewModel: PortViewModel
    /// Shared sampler whose ring buffers feed each tile's sparkline.
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
            RoundedRectangle(cornerRadius: Theme.Liquid.cardCornerRadius, style: .continuous)
                .fill(Theme.Surface.controlBackground.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Liquid.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.Surface.groupedStroke, lineWidth: Theme.Liquid.cardStrokeWidth)
        )
    }
}
