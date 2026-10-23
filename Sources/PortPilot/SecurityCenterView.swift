// SecurityCenterView.swift — Threat findings as an operable incident list.
//
// UX thesis (why this isn't "the Connections tab, red"):
//   A connection table answers "what is connected". An incident list answers
//   "what needs me, and what do I do about it". Every finding card therefore
//   ends in VERBS — Kill, Freeze, Flag — not in more data. Severity uses the
//   fixed Theme.Severity tokens so urgency survives every visual theme, and
//   the empty state distinguishes current results from pending, paused, or
//   degraded monitoring instead of presenting missing evidence as clean.
//
// Structure:
//   - SecurityCenterView: status header + severity filter + finding cards +
//     tuning + history. Pure composition; all state lives in ThreatMonitorStore.
//   - FindingCard: one process, its signals, its actions. Self-contained so
//     the menu-bar dropdown can reuse it later without the page chrome.
//   - Actions route through PortViewModel (kill) and PortManager (freeze)
//     plus BlocklistStore (detection-only flags), then log to the activity store — the same
//     audit trail kills and guard evictions write to.

import SwiftUI
import AppKit

// MARK: - Security Center page

struct SecurityCenterView: View {
    @EnvironmentObject var viewModel: PortViewModel
    @ObservedObject private var appSettings = AppSettings.shared

    @State private var severityFilter: ThreatSeverity?
    @State private var showTuning = false
    @State private var showSecurityFAQ = false
    @State private var actionMessage: String?

    private var threats: ThreatMonitorStore { viewModel.threatMonitor }

    private var visibleFindings: [ThreatFinding] {
        guard let filter = severityFilter else { return threats.findings }
        return threats.findings.filter { $0.severity == filter }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statusHeader
                precautionsBanner
                if threats.consecutiveFailures > 0 {
                    degradedBanner
                }
                severityChips
                if visibleFindings.isEmpty {
                    emptyState
                } else {
                    ForEach(visibleFindings) { finding in
                        FindingCard(finding: finding, onAction: perform(_:_:))
                    }
                }
                tuningSection
                historySection
            }
            .padding(16)
        }
        .sheet(isPresented: $showSecurityFAQ) {
            VStack(spacing: 0) {
                SecurityFAQView()
                HStack {
                    Spacer()
                    Button("Done") { showSecurityFAQ = false }
                        .keyboardShortcut(.cancelAction)
                }
                .padding(12)
            }
            .frame(width: 600, height: 600)
        }
        .overlay(alignment: .bottom) {
            if let message = actionMessage {
                Text(message)
                    .font(appSettings.appFont(size: 12))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Theme.Surface.headerTint)
                    .cornerRadius(8)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Status header

    private var statusHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(statusColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(appSettings.appFont(size: 15, weight: .semibold))
                Text(statusSubtitle)
                    .font(appSettings.appFont(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("Monitor", isOn: monitoringBinding)
                .toggleStyle(.switch)
                .font(appSettings.appFont(size: 12))
            Button("Check now") { threats.checkNow() }
                .buttonStyle(.bordered)
                .font(appSettings.appFont(size: 12))
        }
        .padding(12)
        .background(Theme.Surface.headerTint)
        .cornerRadius(12)
    }

    private var monitoringStatus: ThreatMonitoringStatus {
        ThreatMonitoringStatus(
            isMonitoring: threats.isMonitoring,
            hasAssessment: threats.assessment != nil,
            consecutiveFailures: threats.consecutiveFailures
        )
    }

    private var statusTitle: String {
        switch monitoringStatus {
        case .paused: return "Monitoring paused"
        case .degraded: return "Monitoring degraded — findings may be stale"
        case .pending: return "Waiting for first successful snapshot"
        case .current: break
        }
        if threats.findings.isEmpty { return "No findings in latest successful snapshot" }
        return "\(threats.findings.count) finding\(threats.findings.count == 1 ? "" : "s") to review"
    }

    private var statusIcon: String {
        switch monitoringStatus {
        case .paused: return "pause.circle"
        case .degraded: return "exclamationmark.shield"
        case .pending: return "clock"
        case .current: return threats.findings.isEmpty ? "shield.checkered" : "shield.lefthalf.filled"
        }
    }

    private var statusColor: Color {
        if threats.consecutiveFailures > 0 { return Theme.Severity.warning }
        if monitoringStatus != .current { return .secondary }
        return threats.findings.isEmpty ? Theme.Severity.quiet : Theme.Severity.color(for: threats.assessment?.highestSeverity ?? .warning)
    }

    private var precautionsBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Detection, not prevention", systemImage: "info.circle")
                    .font(appSettings.appFont(size: 12, weight: .semibold))
                Spacer()
                Button("Security FAQ") { showSecurityFAQ = true }
                    .buttonStyle(.bordered)
            }
            Text("Findings are signals to investigate, not malware verdicts. The alert list does not block traffic. Verify the current process before Kill or Freeze; keep existing protections enabled.")
                .font(appSettings.appFont(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Theme.Surface.groupedFill)
        .cornerRadius(10)
    }

    private var statusSubtitle: String {
        var parts: [String] = []
        if let check = threats.lastCheck {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            parts.append("last attempt \(formatter.localizedString(for: check, relativeTo: Date()))")
        } else {
            parts.append("first check pending")
        }
        if let assessment = threats.assessment {
            parts.append("\(assessment.totalConnections) connections · \(assessment.processCount) processes")
        }
        if !threats.isMonitoring { parts.append("monitoring paused") }
        return parts.joined(separator: " · ")
    }

    private var monitoringBinding: Binding<Bool> {
        Binding(
            get: { threats.isMonitoring },
            set: { on in on ? threats.start() : threats.stop() }
        )
    }

    private var degradedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
            Text("Connection snapshots failing (\(threats.consecutiveFailures)×) — findings may be stale, not clean.")
                .font(appSettings.appFont(size: 12))
        }
        .foregroundColor(Theme.Severity.warning)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Severity.warning.opacity(0.12))
        .cornerRadius(10)
    }

    // MARK: - Severity filter

    private var severityChips: some View {
        HStack(spacing: 8) {
            severityChip(label: "All", count: threats.findings.count, active: severityFilter == nil, color: .primary) {
                severityFilter = nil
            }
            ForEach([ThreatSeverity.critical, .warning, .info], id: \.self) { severity in
                let count = threats.findings.filter { $0.severity == severity }.count
                severityChip(
                    label: severity == .critical ? "Critical" : severity == .warning ? "Warning" : "Info",
                    count: count,
                    active: severityFilter == severity,
                    color: Theme.Severity.color(for: severity)
                ) {
                    severityFilter = (severityFilter == severity) ? nil : severity
                }
            }
        }
    }

    private func severityChip(label: String, count: Int, active: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label).font(appSettings.appFont(size: 12, weight: .medium))
                Text(verbatim: "\(count)")
                    .font(appSettings.appMonoFont(size: 11, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background((active ? Color.white : color).opacity(active ? 0.25 : 0.15))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(active ? color.opacity(0.85) : Theme.Surface.headerTint)
            .foregroundColor(active ? .white : .primary)
            .cornerRadius(9)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: statusIcon)
                .font(.system(size: 34))
                .foregroundColor(statusColor)
            Text(severityFilter == nil ? statusTitle : "No findings at this severity")
                .font(appSettings.appFont(size: 13, weight: .semibold))
            Text("No findings is not proof of safety. Monitoring can miss activity between checks; paused or failed checks do not establish a clean state.")
                .font(appSettings.appFont(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: - Tuning

    private var tuningSection: some View {
        DisclosureGroup("Detection tuning", isExpanded: $showTuning) {
            VStack(spacing: 10) {
                tuningStepper("High-connection threshold", value: configBinding(
                    get: { $0.highConnectionThreshold },
                    set: { $0.highConnectionThreshold = $1 }
                ), range: 10...500, help: "Connections per process before flagging (legacy suspect = 50).")
                tuningStepper("Fan-out threshold", value: configBinding(
                    get: { $0.remoteFanoutThreshold },
                    set: { $0.remoteFanoutThreshold = $1 }
                ), range: 3...200, help: "Distinct remotes on one port before flagging a scan shape.")
                tuningStepper("Burst threshold", value: configBinding(
                    get: { $0.newRemoteBurstThreshold },
                    set: { $0.newRemoteBurstThreshold = $1 }
                ), range: 3...200, help: "New remotes for a known process before flagging beaconing.")
                tuningStepper("First-seen minimum", value: configBinding(
                    get: { $0.firstSeenMinConnections },
                    set: { $0.firstSeenMinConnections = $1 }
                ), range: 1...100, help: "Connections before an unknown process is worth a look.")
            }
            .padding(.top, 6)
        }
        .font(appSettings.appFont(size: 13, weight: .medium))
    }

    private func configBinding(get: @escaping (ThreatConfiguration) -> Int, set: @escaping (inout ThreatConfiguration, Int) -> Void) -> Binding<Int> {
        Binding(
            get: { get(threats.configuration) },
            set: {
                set(&threats.configuration, $0)
                threats.applyConfiguration()
            }
        )
    }

    private func tuningStepper(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, help: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(appSettings.appFont(size: 12))
                Spacer()
                Stepper("\(value.wrappedValue)", value: value, in: range)
                    .font(appSettings.appMonoFont(size: 12))
            }
            Text(help).font(appSettings.appFont(size: 11)).foregroundColor(.secondary)
        }
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent history")
                .font(appSettings.appFont(size: 13, weight: .semibold))
            if threats.recentHistory.isEmpty {
                Text("Nothing recorded yet — history is a capped sample of findings, not a complete audit log.")
                    .font(appSettings.appFont(size: 12))
                    .foregroundColor(.secondary)
            } else {
                ForEach(threats.recentHistory.prefix(8)) { finding in
                    HStack(spacing: 8) {
                        Image(systemName: Theme.Severity.icon(for: finding.severity))
                            .foregroundColor(Theme.Severity.color(for: finding.severity))
                            .font(.system(size: 11))
                        Text(finding.processName)
                            .font(appSettings.appFont(size: 12, weight: .medium))
                        Text(finding.detectedAt, style: .relative)
                            .font(appSettings.appFont(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(finding.signals.map { $0.type.title }.joined(separator: ", "))
                            .font(appSettings.appFont(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func perform(_ action: FindingAction, _ finding: ThreatFinding) {
        switch action {
        case .kill:
            guard let identity = finding.processIdentity else {
                flash("Refusing Kill: current process identity is unavailable. Refresh Security Center and verify the process.")
                return
            }
            viewModel.killProcess(identity: identity)
            flash("Kill requested for pid \(finding.pid) — check Activity for the result")
        case .freeze:
            guard let identity = finding.processIdentity else {
                flash("Refusing Freeze: current process identity is unavailable. Refresh Security Center and verify the process.")
                return
            }
            viewModel.pauseProcess(identity: identity)
            flash("Freeze requested for pid \(finding.pid) — check Activity for the result")
        case .copyRemote:
            if let remote = finding.signals.first?.remoteSample {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(remote, forType: .string)
                flash("Copied \(remote)")
            }
        case .blockHost:
            guard let remote = finding.signals.first?.remoteSample else { return }
            let host = ThreatDetector.remoteHost(from: remote)
            do {
                if try BlocklistStore().add(host) {
                    flash("Added \(host) to alert list — traffic is not blocked")
                } else {
                    flash("\(host) is already on the alert list")
                }
            } catch {
                flash("Could not update alert list: \(error)")
            }
        }
    }

    private func flash(_ message: String) {
        actionMessage = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            actionMessage = nil
        }
    }
}

// MARK: - Finding card

/// One flagged process: severity badge, signal rows with plain-language
/// explanations, and verb-first actions. Reusable — the planned menu-bar
/// security glance renders this card without the page around it.
enum FindingAction {
    case kill
    case freeze
    case copyRemote
    case blockHost
}

struct FindingCard: View {
    @ObservedObject private var appSettings = AppSettings.shared
    let finding: ThreatFinding
    let onAction: (FindingAction, ThreatFinding) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: Theme.Severity.icon(for: finding.severity))
                    .foregroundColor(Theme.Severity.color(for: finding.severity))
                Text(finding.processName)
                    .font(appSettings.appFont(size: 14, weight: .semibold))
                Text("pid \(finding.pid) · \(finding.user)")
                    .font(appSettings.appMonoFont(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                severityBadge
            }
            ForEach(finding.signals) { signal in
                VStack(alignment: .leading, spacing: 2) {
                    Text(signal.summary)
                        .font(appSettings.appFont(size: 12, weight: .medium))
                    Text(signal.type.explanation)
                        .font(appSettings.appFont(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 4)
            }
            HStack(spacing: 8) {
                cardButton("Kill", icon: "xmark.octagon.fill", tint: Theme.Severity.critical) {
                    onAction(.kill, finding)
                }
                cardButton("Freeze", icon: "pause.circle.fill", tint: Theme.Severity.warning) {
                    onAction(.freeze, finding)
                }
                cardButton("Copy remote", icon: "doc.on.doc", tint: nil) {
                    onAction(.copyRemote, finding)
                }
                cardButton("Flag host", icon: "flag.fill", tint: nil) {
                    onAction(.blockHost, finding)
                }
                .help("Add to the alert blocklist for detection only; does not stop traffic. Cached matching may take up to 60 seconds to refresh.")
            }
        }
        .padding(12)
        .background(Theme.Surface.headerTint)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.Severity.color(for: finding.severity).opacity(0.45), lineWidth: 1)
        )
    }

    private var severityBadge: some View {
        Text(finding.severity == .critical ? "CRITICAL" : finding.severity == .warning ? "WARNING" : "INFO")
            .font(appSettings.appMonoFont(size: 10, weight: .bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Theme.Severity.color(for: finding.severity))
            .foregroundColor(.white)
            .cornerRadius(6)
    }

    private func cardButton(_ label: String, icon: String, tint: Color?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(appSettings.appFont(size: 12, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background((tint ?? Color.secondary).opacity(0.15))
                .foregroundColor(tint ?? .primary)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
