// ThreatModels.swift — Data model for the PortPilot threat engine (v1).
//
// What this file is:
//   The vocabulary every threat surface shares — the macOS Security Center,
//   `portpilot connections --threats`, and the TUI threats filter all render
//   these same types, so a signal means the same thing everywhere.
//
// What this file is NOT:
//   - It runs no detection (see ThreatDetector.swift).
//   - It performs no I/O (see ThreatHistoryStore.swift, BlocklistStore.swift).
//   - It draws no UI. Severity-to-color mapping lives in each frontend.
//
// How to expand it:
//   - New signal kind? Add a case to ThreatSignalType with a stable raw value
//     (raw values persist in threat-history.json — never rename one; add).
//   - New tuning knob? Add a field to ThreatConfiguration with a default so
//     existing persisted configs keep decoding.
//   - Heavier v2 signals (GeoIP, JA3, process lineage) attach as optional
//     context on ThreatSignal rather than new top-level types.

import Foundation

// MARK: - Monitoring status

/// Presentation state, independent of whether a snapshot contains findings.
/// Only `.current` permits describing the latest assessment as a monitored result.
public enum ThreatMonitoringStatus: Equatable, Sendable {
    case paused
    case degraded
    case pending
    case current

    public init(isMonitoring: Bool, hasAssessment: Bool, consecutiveFailures: Int) {
        if !isMonitoring {
            self = .paused
        } else if consecutiveFailures > 0 {
            self = .degraded
        } else if !hasAssessment {
            self = .pending
        } else {
            self = .current
        }
    }
}

// MARK: - Severity

/// Severity of a threat signal or finding. Ordered so findings sort with the
/// most urgent first and the monitor can escalate with a single comparison.
public enum ThreatSeverity: String, Codable, Sendable, CaseIterable, Comparable {
    case info
    case warning
    case critical

    public static func < (lhs: ThreatSeverity, rhs: ThreatSeverity) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }
}

// MARK: - Signal type

/// The detection rules understood by ThreatDetector. Each case documents the
/// heuristic it represents and the configuration knob that tunes it.
///
/// Expansion rule: rules are additive. A new case needs a matching rule
/// method in ThreatDetector plus display copy in `title`/`explanation`.
public enum ThreatSignalType: String, Codable, Sendable, CaseIterable {
    /// A connection's remote endpoint matches the user's blocklist.
    case blocklistedRemote
    /// One process holds more established connections than
    /// `ThreatConfiguration.highConnectionThreshold`.
    case highConnectionCount
    /// Many distinct remotes converge on one local port
    /// (`remoteFanoutThreshold`) — port-scan or botnet-knock shape.
    case remoteFanout
    /// A known executable identity talks to many never-before-seen remotes
    /// (`newRemoteBurstThreshold`) — beaconing / C2 shape.
    case newRemoteBurst
    /// An executable identity the baseline has never seen is dialing out
    /// (`firstSeenMinConnections`) — unknown-binary shape.
    case firstSeenDialer

    /// Short label for tables, badges, and notification titles.
    public var title: String {
        switch self {
        case .blocklistedRemote: return "Blocklisted remote"
        case .highConnectionCount: return "High connection count"
        case .remoteFanout: return "Remote fan-out"
        case .newRemoteBurst: return "New-remote burst"
        case .firstSeenDialer: return "First-seen dialer"
        }
    }

    /// One-line plain-language explanation for detail views and `--threats`.
    public var explanation: String {
        switch self {
        case .blocklistedRemote:
            return "Remote endpoint matches your alert list — review it; this does not block traffic."
        case .highConnectionCount:
            return "Process crossed the configured connection-count threshold — check whether the activity is expected."
        case .remoteFanout:
            return "Many distinct remotes converge on one local port — review the service and its clients."
        case .newRemoteBurst:
            return "A familiar executable identity is contacting many new remotes — verify the activity."
        case .firstSeenDialer:
            return "An executable identity is new to this session's baseline and has several connections — verify it."
        }
    }
}

// MARK: - Signal

/// One fired rule. Signals are the unit of cooldown: the monitor suppresses
/// repeat notifications per `dedupKey`, not per finding, so a finding that
/// gains a second signal still pages once for the new signal.
public struct ThreatSignal: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let type: ThreatSignalType
    public let severity: ThreatSeverity
    public let processName: String
    public let pid: Int
    /// Local port under pressure, when the rule is port-scoped (fan-out).
    public let localPort: Int?
    /// Human-readable one-liner, e.g. "web-proxy holds 132 connections (>50)".
    public let summary: String
    /// Example remote endpoint for context (never the full list — lists live
    /// behind the detail view / `--json`).
    public let remoteSample: String
    /// The count that tripped the rule.
    public let count: Int

    public init(
        type: ThreatSignalType,
        severity: ThreatSeverity,
        processName: String,
        pid: Int,
        localPort: Int? = nil,
        summary: String,
        remoteSample: String,
        count: Int
    ) {
        self.type = type
        self.severity = severity
        self.processName = processName
        self.pid = pid
        self.localPort = localPort
        self.summary = summary
        self.remoteSample = remoteSample
        self.count = count
        self.id = "\(type.rawValue)-\(processName)-\(pid)-\(localPort.map(String.init) ?? "-")"
    }

    /// Stable key for notification cooldowns and history dedup.
    public var dedupKey: String { id }
}

// MARK: - Finding

/// All signals for one process in a single assessment. The finding's severity
/// is the max of its signals so sorting and badges need one comparison.
public struct ThreatFinding: Codable, Sendable, Identifiable {
    public let id: String
    public let processName: String
    public let pid: Int
    public let user: String
    /// Incarnation captured with the connection snapshot. Nil means the OS
    /// could not establish action authority; Kill/Freeze must then fail closed.
    public let processIdentity: ProcessIdentity?
    public let signals: [ThreatSignal]
    public let detectedAt: Date

    public init(processName: String, pid: Int, user: String, processIdentity: ProcessIdentity? = nil, signals: [ThreatSignal], detectedAt: Date = Date()) {
        self.processName = processName
        self.pid = pid
        self.user = user
        self.processIdentity = processIdentity
        self.signals = signals
        self.detectedAt = detectedAt
        let signalKeys = signals.map { $0.type.rawValue }.sorted().joined(separator: "+")
        self.id = "\(processName)-\(pid)-\(signalKeys)"
    }

    /// Highest severity across signals. `.info` when (defensively) empty.
    public var severity: ThreatSeverity {
        signals.map { $0.severity }.max() ?? .info
    }
}

// MARK: - Assessment

/// The result of one detector pass over a connection snapshot. Value type on
/// purpose: snapshots flow across threads (poller queue → UI) and must not
/// be mutated in flight.
public struct ThreatAssessment: Sendable {
    public let findings: [ThreatFinding]
    public let generatedAt: Date
    public let totalConnections: Int
    public let processCount: Int

    public init(findings: [ThreatFinding], generatedAt: Date = Date(), totalConnections: Int, processCount: Int) {
        // Urgent first; stable tiebreak so renders don't jitter between polls.
        self.findings = findings.sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return $0.processName < $1.processName
        }
        self.generatedAt = generatedAt
        self.totalConnections = totalConnections
        self.processCount = processCount
    }

    /// Highest severity present, or nil when the snapshot is clean.
    public var highestSeverity: ThreatSeverity? {
        findings.map { $0.severity }.max()
    }

    public var isClean: Bool { findings.isEmpty }
}

// MARK: - Configuration

/// Tuning knobs for the detector. Every threshold has a default matching the
/// legacy behavior (`highConnectionThreshold = 50` preserves the old
/// "suspect" definition), so enabling the engine never redefines existing
/// alerts out from under the user.
public struct ThreatConfiguration: Codable, Sendable {
    /// Connections per process before `highConnectionCount` fires.
    public var highConnectionThreshold: Int
    /// Distinct remotes on one local port before `remoteFanout` fires.
    public var remoteFanoutThreshold: Int
    /// Unseen remotes for a known executable identity before `newRemoteBurst` fires.
    public var newRemoteBurstThreshold: Int
    /// Minimum connections before an unknown executable identity earns `firstSeenDialer`.
    public var firstSeenMinConnections: Int
    /// Rules the user has switched off. Empty means all rules armed.
    public var disabledSignals: Set<String>

    public init(
        highConnectionThreshold: Int = 50,
        remoteFanoutThreshold: Int = 15,
        newRemoteBurstThreshold: Int = 10,
        firstSeenMinConnections: Int = 5,
        disabledSignals: Set<String> = []
    ) {
        self.highConnectionThreshold = highConnectionThreshold
        self.remoteFanoutThreshold = remoteFanoutThreshold
        self.newRemoteBurstThreshold = newRemoteBurstThreshold
        self.firstSeenMinConnections = firstSeenMinConnections
        self.disabledSignals = disabledSignals
    }

    public static let `default` = ThreatConfiguration()

    /// False when the user disabled this rule in settings.
    public func isEnabled(_ type: ThreatSignalType) -> Bool {
        !disabledSignals.contains(type.rawValue)
    }
}

// MARK: - Baseline

/// What "normal" looks like: processes seen before and, per process, the
/// remotes they have talked to. The detector diffs each snapshot against
/// this; the monitor owns the single mutable copy and advances it after
/// every assessment.
///
/// v1 is deliberately behavioral, not statistical: no means or variances to
/// tune, just "have we seen this before". Statistical baselines (per-hour
/// profiles, decay) are the documented v2 upgrade and slot into this same
/// type without changing the detector's call signature.
public struct ThreatBaseline: Sendable {
    /// False until the first successful snapshot has been observed. This is
    /// snapshot state, so an empty but valid poll initializes it too.
    public private(set) var isSeeded: Bool
    public private(set) var knownIdentities: Set<String>
    public private(set) var knownRemotesByIdentity: [String: Set<String>]
    private var pendingIdentityObservations: [String: Int]
    private var pendingRemoteObservations: [String: [String: Int]]

    public init(
        isSeeded: Bool = false,
        knownIdentities: Set<String> = [],
        knownRemotesByIdentity: [String: Set<String>] = [:]
    ) {
        self.isSeeded = isSeeded
        self.knownIdentities = knownIdentities
        self.knownRemotesByIdentity = knownRemotesByIdentity
        self.pendingIdentityObservations = [:]
        self.pendingRemoteObservations = [:]
    }

    /// Prefer the resolved executable path. If inspection is denied, bind the
    /// fallback to PID so another binary cannot inherit trust by reusing a name.
    public static func identity(for connection: EstablishedConnection) -> String {
        let user = connection.user.lowercased()
        if let rawPath = connection.executablePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawPath.isEmpty {
            return "\(user)|path:\(URL(fileURLWithPath: rawPath).standardizedFileURL.path)"
        }
        return "\(user)|name:\(connection.processName.lowercased())|pid:\(connection.pid)"
    }

    public func contains(_ connection: EstablishedConnection) -> Bool {
        knownIdentities.contains(Self.identity(for: connection))
    }

    public func unseenRemotes(for connection: EstablishedConnection, remotes: Set<String>) -> Set<String> {
        let known = knownRemotesByIdentity[Self.identity(for: connection)] ?? []
        return remotes.subtracting(known)
    }

    /// Advance exactly once per complete snapshot. New executable identities
    /// and remotes must recur before becoming trusted, so one poisoned poll
    /// cannot redefine normal behavior.
    public mutating func advanceSnapshot(
        _ connections: [EstablishedConnection],
        promotionThreshold: Int = 2
    ) {
        let threshold = max(2, promotionThreshold)
        let grouped = Dictionary(grouping: connections, by: Self.identity)
        let observedIdentities = Set(grouped.keys)

        pendingIdentityObservations = pendingIdentityObservations.filter { observedIdentities.contains($0.key) }
        pendingRemoteObservations = pendingRemoteObservations.filter { observedIdentities.contains($0.key) }

        for (identity, identityConnections) in grouped {
            let remotes = Set(identityConnections.map { ThreatDetector.remoteHost(from: $0.remoteAddress) })
            if !knownIdentities.contains(identity) {
                let count = pendingIdentityObservations[identity, default: 0] + 1
                if count >= threshold {
                    knownIdentities.insert(identity)
                    pendingIdentityObservations.removeValue(forKey: identity)
                } else {
                    pendingIdentityObservations[identity] = count
                }
            }

            // A recurring executable does not make a newly observed remote
            // recurring. Track each remote from the first candidate snapshot,
            // independently of identity promotion.
            let known = knownRemotesByIdentity[identity] ?? []
            let unseen = remotes.subtracting(known)
            var pending = pendingRemoteObservations[identity] ?? [:]
            pending = pending.filter { unseen.contains($0.key) }
            for remote in unseen {
                let count = pending[remote, default: 0] + 1
                if count >= threshold {
                    knownRemotesByIdentity[identity, default: []].insert(remote)
                    pending.removeValue(forKey: remote)
                } else {
                    pending[remote] = count
                }
            }
            pendingRemoteObservations[identity] = pending
        }
        isSeeded = true
    }
}
