import SwiftUI

// MARK: - Main Status Bar

/// Footer strip distinguishes monitor freshness from finding severity.
struct MainStatusBar: View {
    /// View model whose alert state, refresh time, and counts I render.
    @ObservedObject var viewModel: PortViewModel
    @ObservedObject private var appSettings = AppSettings.shared

    private var healthTint: Color {
        viewModel.threatMonitor.chromePresentation.chromeColor
    }

    private var healthLabel: String {
        viewModel.threatMonitor.chromePresentation.headline
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
                Text("Port refresh")
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
                    .fill(healthTint)
                    .frame(width: 5, height: 5)
                Text(viewModel.threatMonitor.chromePresentation.cadenceLabel)
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

extension ThreatMonitorStore {
    var chromePresentation: MonitoringPresentation {
        MonitoringPresentation(
            status: ThreatMonitoringStatus(
                isMonitoring: isMonitoring,
                hasAssessment: assessment != nil,
                consecutiveFailures: consecutiveFailures
            ),
            highestSeverity: assessment?.highestSeverity,
            pollInterval: pollInterval
        )
    }
}

extension MonitoringPresentation {
    var chromeColor: Color {
        switch status {
        case .paused, .pending: return .secondary
        case .degraded: return Theme.Status.warning
        case .current:
            switch highestSeverity {
            case .critical: return Theme.Action.kill
            case .warning: return Theme.Status.warning
            case .info: return .secondary
            case nil: return Theme.Status.connected
            }
        }
    }
}
