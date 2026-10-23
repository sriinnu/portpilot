// ThreatMonitorStore.swift — Background auto-alert engine for the macOS app.
//
// What this is:
//   A heuristic poll loop snapshots established connections, runs ThreatDetector against a
//   learning baseline, and pages the user ONLY for novel signals — with a
//   per-signal cooldown so a sustained attack buzzes once, not 240 times.
//
// Threading (mirrors PortGuardStore — read that first):
//   - Polling and detection run on a private utility queue; lsof never
//     touches the main thread.
//   - @Published state and the activity log are main-confined; every publish
//     hops via `Task { @MainActor }`.
//   - `baseline`, `cooldowns`, the timer, and the in-flight flag are
//     queue-confined. The one exception is `configuration`, which the
//     Security Center edits on main and the tick snapshots under lock.
//
// Anti-spam contract:
//   - Absolute rules run on the first complete snapshot. Baseline-relative
//     rules wait for initialization; new identities/remotes quarantine before promotion.
//   - A signal notifies at most once per `cooldown` (default 15 min).
//   - Simultaneous novel signals coalesce into ONE summary notification,
//     not one banner per signal.
//   - All gating honors the global notifications switch: when the user mutes
//     PortPilot, the monitor still tracks (Security Center stays live) but
//     posts nothing.
//
// Expansion:
//   - Severity-gated actions (auto-quarantine criticals) slot into
//     `handleNovelFindings` behind a configuration flag — the plumbing
//     (finding → action → log) already exists.
//   - Statistical baselines replace ThreatBaseline without touching this
//     file: the store only calls observe/unseenRemotes.

import Foundation
import Combine
import UserNotifications

/// Background threat monitor: poll → detect → learn → page-if-novel.
final class ThreatMonitorStore: ObservableObject {

    /// Latest assessment for the Security Center. Nil until the first tick.
    @Published private(set) var assessment: ThreatAssessment?
    /// Findings from the latest tick (empty when clean).
    @Published private(set) var findings: [ThreatFinding] = []
    /// Whether the poll loop is running. Toggle from the Security Center.
    @Published private(set) var isMonitoring: Bool = false
    /// When the last snapshot completed. Nil before the first tick.
    @Published private(set) var lastCheck: Date?
    /// Consecutive snapshot failures (lsof flakiness). Resets on success.
    /// Surfaced in the Security Center so "no findings" never ambiguously
    /// means "not looking".
    @Published private(set) var consecutiveFailures: Int = 0

    /// Tuning knobs. Edits apply on the next tick — no restart needed.
    @Published var configuration = ThreatConfiguration.default

    /// Seconds between snapshots. 15 balances alert latency against an
    /// lsof every tick. Below 5 is refused (hot loop on a slow syscall).
    @Published var pollInterval: TimeInterval = 15 {
        didSet {
            if pollInterval < 5 { pollInterval = 5 }
            restartTimerIfMonitoring()
        }
    }

    /// Minimum seconds between two notifications for the same signal.
    /// Prevents a sustained attack from buzzing every poll.
    var cooldown: TimeInterval = 15 * 60

    private let log: ActivityLogStore
    private let portManager = PortManager()
    private let history = ThreatHistoryStore()
    private let queue = DispatchQueue(label: "com.portpilot.threats", qos: .utility)
    private let lock = NSLock()

    /// Queue-confined: what "normal" looks like. Learns every tick.
    private var baseline = ThreatBaseline()
    /// Queue-confined: dedupKey → last notification date.
    private var cooldowns: [String: Date] = [:]
    /// Queue-confined poll timer.
    private var timer: DispatchSourceTimer?
    /// Queue-confined: skips a tick while the previous lsof still runs.
    private var tickInProgress = false

    init(log: ActivityLogStore) {
        self.log = log
        start()
    }

    deinit {
        timer?.cancel()
    }

    // MARK: - Control

    /// Start the poll loop. Idempotent — safe to call on appear and on
    /// settings apply.
    func start() {
        applyConfiguration()
        queue.async { [weak self] in
            guard let self else { return }
            guard self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: self.pollInterval)
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            self.timer = timer
            Task { @MainActor [weak self] in self?.isMonitoring = true }
        }
    }

    /// Stop the loop. Baseline and history survive — restarting doesn't
    /// re-accuse the machine.
    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.timer?.cancel()
            self.timer = nil
            Task { @MainActor [weak self] in self?.isMonitoring = false }
        }
    }

    /// Recent forensic trail for the Security Center's history section.
    var recentHistory: [ThreatFinding] { history.recent(limit: 20) }

    /// Force an immediate assessment (Security Center "Check now").
    func checkNow() {
        queue.async { [weak self] in self?.tick() }
    }

    // MARK: - Poll loop (queue-confined)

    private func restartTimerIfMonitoring() {
        queue.async { [weak self] in
            guard let self, self.timer != nil else { return }
            self.timer?.cancel()
            self.timer = nil
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + self.pollInterval, repeating: self.pollInterval)
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            self.timer = timer
        }
    }

    private func tick() {
        guard !tickInProgress else { return }
        tickInProgress = true
        defer { tickInProgress = false }

        let config = configurationSnapshot()
        let connections: [EstablishedConnection]
        do {
            connections = try portManager.getAllConnections()
        } catch {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.consecutiveFailures += 1
                self.lastCheck = Date()
            }
            return
        }

        let result = ThreatDetector.assess(
            connections: connections,
            isBlocklisted: { [portManager] in portManager.isBlocklisted(connection: $0) },
            configuration: config,
            baseline: baseline
        )

        // Advance only after a complete snapshot. New executable identities
        // and remotes remain quarantined until they recur.
        baseline.advanceSnapshot(connections)

        history.record(result.findings)

        // Absolute rules must surface on the first tick. Baseline-relative
        // rules are already suppressed by the detector while unseeded.
        let now = Date()
        var novel: [ThreatFinding] = []
        for finding in result.findings {
            let fresh = finding.signals.filter { signal in
                guard let last = cooldowns[signal.dedupKey] else { return true }
                return now.timeIntervalSince(last) >= cooldown
            }
            guard !fresh.isEmpty else { continue }
            novel.append(ThreatFinding(
                processName: finding.processName,
                pid: finding.pid,
                user: finding.user,
                processIdentity: finding.processIdentity,
                signals: fresh,
                detectedAt: finding.detectedAt
            ))
        }
        for finding in novel {
            for signal in finding.signals { cooldowns[signal.dedupKey] = now }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.assessment = result
            self.findings = result.findings
            self.lastCheck = now
            self.consecutiveFailures = 0
            if !novel.isEmpty {
                self.handleNovelFindings(novel)
            }
        }
    }

    /// Queue-confined: read the mirrored configuration under lock. The tick
    /// never touches `configuration` directly — direct cross-thread reads of
    /// @Published state race. See applyConfiguration().
    private func configurationSnapshot() -> ThreatConfiguration {
        lock.lock()
        defer { lock.unlock() }
        // @Published is main-confined; tick runs on queue — hop synchronously
        // through the lock-protected mirror updated in the didSet below.
        return mirroredConfiguration
    }

    private var mirroredConfiguration = ThreatConfiguration.default

    /// Log + notify for novel findings. ONE summary notification per tick no
    /// matter how many signals fired — the detail lives in the Security
    /// Center, not in a banner stack.
    @MainActor
    private func handleNovelFindings(_ novel: [ThreatFinding]) {
        for finding in novel {
            let kinds = finding.signals.map { $0.type.title }.joined(separator: ", ")
            log.add(
                source: "threat",
                message: "\(finding.processName) (pid \(finding.pid)): \(kinds)",
                level: finding.severity == .critical ? .error : .warning
            )
        }
        NotificationManager.shared.sendThreatSummaryNotification(findings: novel)
    }
}

// MARK: - Configuration mirroring

extension ThreatMonitorStore {
    /// Push edited knobs to the queue-confined tick. MUST be called on main
    /// (all editors live there): it snapshots `configuration` synchronously
    /// and hands the copy across threads, so the tick never races the UI.
    /// `start()` calls this; Security Center steppers call it per edit.
    func applyConfiguration() {
        let config = configuration
        queue.async { [weak self] in
            self?.lock.lock()
            self?.mirroredConfiguration = config
            self?.lock.unlock()
        }
    }
}

// MARK: - Threat summary notifications

extension NotificationManager {
    /// Coalesced threat page: one banner per tick, urgent-first copy, with a
    /// "Open Security Center" action. Respects the global notifications
    /// switch — muted means silent tracking, never silent loss (the Security
    /// Center still shows everything).
    func sendThreatSummaryNotification(findings: [ThreatFinding]) {
        guard notificationsEnabled, !findings.isEmpty else { return }
        let criticals = findings.filter { $0.severity == .critical }
        let title: String
        let body: String
        if !criticals.isEmpty {
            let names = criticals.prefix(2).map { $0.processName }.joined(separator: ", ")
            title = "Threat: blocklisted contact"
            body = criticals.count == 1
                ? "\(names) talks to a blocklisted host — open Security Center to act"
                : "\(criticals.count) processes talk to blocklisted hosts (e.g. \(names))"
        } else if findings.count == 1, let only = findings.first {
            title = "Possible bot activity"
            body = "\(only.processName): \(only.signals.map { $0.summary }.joined(separator: "; "))"
        } else {
            title = "Possible bot activity"
            body = "\(findings.count) processes tripped threat rules — open Security Center to review"
        }
        sendThreatNotification(title: title, body: body)
    }

    private func sendThreatNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.threatCategoryIdentifier
        let request = UNNotificationRequest(
            identifier: "threat-summary-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to send threat notification: \(error)")
            }
        }
    }
}
