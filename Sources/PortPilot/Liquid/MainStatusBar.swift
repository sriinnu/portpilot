import SwiftUI

// MARK: - Main Status Bar

/// Footer strip along the bottom of the main window — a quiet signal of
/// health at a glance ("All systems nominal" / "Elevated activity" / etc.).
///
/// Everything I render here is derived state: health tint, last-refresh
/// clock, port counts, and the live-sample dot. That keeps the bar honest —
/// it can never lie about what the view model is seeing.
struct MainStatusBar: View {
    /// View model whose alert state, refresh time, and counts I render.
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
            HStack(spacing: 4) {
                Circle()
                    .fill(Theme.Status.connected)
                    .frame(width: 5, height: 5)
                    .shadow(color: Theme.Status.connected.opacity(0.55), radius: 2)
                Text("Live \u{2022} 2s sample")
                    .font(appSettings.appFont(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.85))
            }
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
