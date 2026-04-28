import SwiftUI

// MARK: - Live Traffic Strip (Menubar)

/// Four compact metric tiles rendered across the top of the menubar dropdown.
///
/// Each tile pairs a label and current value with a mini sparkline. The
/// "Active" tile wears a live-pulse dot whose colour I drive from the shared
/// `AlertState`, so the menubar glance always agrees with the main window.
struct LiveTrafficStrip: View {
    /// Current count of active (non-socket) ports.
    let active: Int
    /// Current count of Unix sockets.
    let sockets: Int
    /// Current count of established connections.
    let connections: Int
    /// Current aggregate CPU% across active ports.
    let cpu: Double
    /// Sparkline history for the "Active" tile.
    let activeHistory: [Double]
    /// Sparkline history for the "Sockets" tile.
    let socketsHistory: [Double]
    /// Sparkline history for the "Conns" tile.
    let connectionsHistory: [Double]
    /// Sparkline history for the "CPU" tile.
    let cpuHistory: [Double]
    /// Drives the pulse-dot colour on the Active tile.
    let alertState: AlertState

    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        HStack(spacing: 8) {
            tile(label: "Active", value: "\(active)", history: activeHistory, pulse: true, dotColor: pulseDotColor)
            tile(label: "Sockets", value: "\(sockets)", history: socketsHistory)
            tile(label: "Conns", value: "\(connections)", history: connectionsHistory)
            tile(label: "CPU", value: String(format: "%.0f%%", cpu), history: cpuHistory, accent: Theme.Status.warning)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private var pulseDotColor: Color {
        switch alertState {
        case .normal: return Theme.Alert.dotActive
        case .warning: return Theme.Alert.dotWarning
        case .critical: return Theme.Alert.dotCritical
        }
    }

    private func tile(label: String, value: String, history: [Double], pulse: Bool = false, dotColor: Color = Theme.Liquid.sparklinePulse, accent: Color? = nil) -> some View {
        let stroke = accent ?? Theme.Liquid.sparklineStroke
        let fill = (accent ?? Theme.Liquid.sparklineStroke).opacity(0.18)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if pulse {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 5, height: 5)
                        .shadow(color: dotColor.opacity(0.6), radius: 2)
                }
                Text(label)
                    .font(appSettings.appFont(size: 9, weight: .semibold))
                    .foregroundColor(Theme.Liquid.metricLabel)
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            Text(value)
                .font(appSettings.appMonoFont(size: 15, weight: .bold))
                .foregroundColor(Theme.Liquid.metricValue)
                .lineLimit(1).minimumScaleFactor(0.7)
            Sparkline(values: history, stroke: stroke, fill: fill, lineWidth: 1.1)
                .frame(height: 14)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Liquid.tileCornerRadius, style: .continuous).fill(Theme.Liquid.metricTileBackground))
        .overlay(RoundedRectangle(cornerRadius: Theme.Liquid.tileCornerRadius, style: .continuous).strokeBorder(Theme.Liquid.metricTileStroke, lineWidth: Theme.Liquid.cardStrokeWidth))
    }
}
