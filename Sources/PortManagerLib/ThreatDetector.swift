// ThreatDetector.swift — Pure detection rules for the PortPilot threat engine.
//
// Design contract (read before adding a rule):
//   - PURE. No I/O, no singletons, no clock reads except via the `now`
//     parameter. Every rule is a private static method over its inputs, so
//     the full engine is unit-testable with fabricated snapshots — the test
//     suite must never shell out to lsof/ss (see Package.swift).
//   - INJECTED blocklist. The detector takes `isBlocklisted` as a closure
//     instead of reaching for PortManager so tests stub it and the app/CLI
//     pass the real matcher. Same for every future external lookup (GeoIP,
//     reputation feeds): closure in, signal out.
//   - ADDITIVE rules. A new rule is a new ThreatSignalType case + one method
//     + one call site in assess(). Never change what an existing rule means;
//     gate behavior changes behind ThreatConfiguration fields with defaults.
//   - AGGREGATE per process. One signal per (rule, process[, port]) — never
//     one per connection. Connection-level detail belongs in --json and the
//     detail view, not in findings.
//
// v1 rule set (see docs/THREAT_ENGINE.md for rationale and thresholds):
//   1. blocklistedRemote  (critical) — remote matches the user blocklist.
//   2. highConnectionCount (warning) — per-process count over threshold.
//   3. remoteFanout        (warning) — distinct remotes on one local port.
//   4. newRemoteBurst      (warning) — known executable, many unseen remotes.
//   5. firstSeenDialer     (info)    — unknown executable identity dialing out.

import Foundation

/// Stateless threat detection. All methods are static; there is nothing to
/// instantiate, reset, or leak between assessments.
public enum ThreatDetector {

    // MARK: - Entry point

    /// Run every enabled rule over one connection snapshot.
    ///
    /// - Parameters:
    ///   - connections: One `getAllConnections()` snapshot (enrichment of
    ///     `isBlocklisted` is NOT required — the detector re-checks via the
    ///     injected closure so callers can pass raw snapshots).
    ///   - isBlocklisted: Blocklist matcher (normally
    ///     the checked `EstablishedConnection.isBlocklisted` snapshot field).
    ///   - configuration: Thresholds and per-rule kill switches.
    ///   - baseline: What "normal" looks like. Unseeded baselines skip
    ///     baseline-relative rules (4–5); absolute rules still run.
    /// - Returns: An assessment with findings sorted urgent-first.
    public static func assess(
        connections: [EstablishedConnection],
        isBlocklisted: (EstablishedConnection) -> Bool,
        configuration: ThreatConfiguration = .default,
        baseline: ThreatBaseline = ThreatBaseline()
    ) -> ThreatAssessment {
        let grouped = Dictionary(grouping: connections, by: { $0.pid })
        var findings: [ThreatFinding] = []

        for (pid, conns) in grouped {
            guard let first = conns.first else { continue }
            var signals: [ThreatSignal] = []

            if configuration.isEnabled(.blocklistedRemote),
               let signal = blocklistedSignal(connections: conns, processName: first.processName, pid: pid, isBlocklisted: isBlocklisted) {
                signals.append(signal)
            }
            if configuration.isEnabled(.highConnectionCount),
               let signal = highConnectionSignal(connections: conns, processName: first.processName, pid: pid, threshold: configuration.highConnectionThreshold) {
                signals.append(signal)
            }
            if configuration.isEnabled(.remoteFanout) {
                signals.append(contentsOf: fanoutSignals(
                    connections: conns,
                    processName: first.processName,
                    pid: pid,
                    threshold: configuration.remoteFanoutThreshold
                ))
            }
            if baseline.isSeeded {
                if configuration.isEnabled(.newRemoteBurst),
                   let signal = newRemoteBurstSignal(
                       connections: conns,
                       identityConnection: first,
                       pid: pid,
                       baseline: baseline,
                       threshold: configuration.newRemoteBurstThreshold
                   ) {
                    signals.append(signal)
                }
                if configuration.isEnabled(.firstSeenDialer),
                   let signal = firstSeenDialerSignal(
                       connections: conns,
                       identityConnection: first,
                       pid: pid,
                       baseline: baseline,
                       minConnections: configuration.firstSeenMinConnections
                   ) {
                    signals.append(signal)
                }
            }

            if !signals.isEmpty {
                findings.append(ThreatFinding(
                    processName: first.processName,
                    pid: pid,
                    user: first.user,
                    processIdentity: ProcessIdentity(connection: first),
                    signals: signals
                ))
            }
        }

        return ThreatAssessment(
            findings: findings,
            totalConnections: connections.count,
            processCount: grouped.count
        )
    }

    // MARK: - Rules (one method each; keep them independent)

    /// Rule 1 — any connection in the group matches the blocklist.
    private static func blocklistedSignal(
        connections: [EstablishedConnection],
        processName: String,
        pid: Int,
        isBlocklisted: (EstablishedConnection) -> Bool
    ) -> ThreatSignal? {
        let hits = connections.filter(isBlocklisted)
        guard !hits.isEmpty else { return nil }
        let sample = hits.first?.remoteAddress ?? "-"
        return ThreatSignal(
            type: .blocklistedRemote,
            severity: .critical,
            processName: processName,
            pid: pid,
            summary: "\(processName) talks to \(hits.count) blocklisted endpoint\(hits.count == 1 ? "" : "s")",
            remoteSample: sample,
            count: hits.count
        )
    }

    /// Rule 2 — per-process connection count over threshold. This preserves
    /// the legacy "suspect" (>50) definition when the default config applies.
    private static func highConnectionSignal(
        connections: [EstablishedConnection],
        processName: String,
        pid: Int,
        threshold: Int
    ) -> ThreatSignal? {
        guard connections.count > threshold else { return nil }
        return ThreatSignal(
            type: .highConnectionCount,
            severity: .warning,
            processName: processName,
            pid: pid,
            summary: "\(processName) holds \(connections.count) connections (> \(threshold))",
            remoteSample: connections.first?.remoteAddress ?? "-",
            count: connections.count
        )
    }

    /// Rule 3 — distinct remote hosts converging on one local port. Grouped
    /// by parsed local port so one scanned service yields one signal, not one
    /// per connection. Unparseable local endpoints group under their raw
    /// address string via the `fallback:` key path below.
    private static func fanoutSignals(
        connections: [EstablishedConnection],
        processName: String,
        pid: Int,
        threshold: Int
    ) -> [ThreatSignal] {
        let byLocalPort = Dictionary(grouping: connections) { localPortLabel(for: $0.localAddress) }
        var signals: [ThreatSignal] = []
        for (label, conns) in byLocalPort {
            let distinctRemotes = Set(conns.map { remoteHost(from: $0.remoteAddress) })
            guard distinctRemotes.count >= threshold else { continue }
            signals.append(ThreatSignal(
                type: .remoteFanout,
                severity: .warning,
                processName: processName,
                pid: pid,
                localPort: Int(label),
                summary: "\(distinctRemotes.count) distinct remotes on :\(label) — scan or knock shape",
                remoteSample: conns.first?.remoteAddress ?? "-",
                count: distinctRemotes.count
            ))
        }
        return signals
    }

    /// Rule 4 — a known executable identity talks to many unseen remotes.
    private static func newRemoteBurstSignal(
        connections: [EstablishedConnection],
        identityConnection: EstablishedConnection,
        pid: Int,
        baseline: ThreatBaseline,
        threshold: Int
    ) -> ThreatSignal? {
        let remotes = Set(connections.map { remoteHost(from: $0.remoteAddress) })
        let unseen = baseline.unseenRemotes(for: identityConnection, remotes: remotes)
        guard unseen.count >= threshold else { return nil }
        return ThreatSignal(
            type: .newRemoteBurst,
            severity: .warning,
            processName: identityConnection.processName,
            pid: pid,
            summary: "\(identityConnection.processName) talks to \(unseen.count) new remotes — beaconing shape",
            remoteSample: unseen.sorted().first ?? "-",
            count: unseen.count
        )
    }

    /// Rule 5 — an executable identity absent from the baseline is dialing out. Info, not
    /// warning: new dev servers and updaters trip this legitimately. The
    /// Security Center renders it as "verify me", not "kill me".
    private static func firstSeenDialerSignal(
        connections: [EstablishedConnection],
        identityConnection: EstablishedConnection,
        pid: Int,
        baseline: ThreatBaseline,
        minConnections: Int
    ) -> ThreatSignal? {
        guard !baseline.contains(identityConnection) else { return nil }
        guard connections.count >= minConnections else { return nil }
        return ThreatSignal(
            type: .firstSeenDialer,
            severity: .info,
            processName: identityConnection.processName,
            pid: pid,
            summary: "First-seen executable \(identityConnection.processName) dials out (\(connections.count) connections) — verify the binary",
            remoteSample: connections.first?.remoteAddress ?? "-",
            count: connections.count
        )
    }

    // MARK: - Address helpers

    /// Host part of a `host:port` / `[v6]:port` remote endpoint. Mirrors the
    /// parsing in `BlocklistEntry.matches` (brackets, last-colon split) so
    /// detector grouping and blocklist matching agree on identity.
    public static func remoteHost(from remoteAddress: String) -> String {
        if remoteAddress.hasPrefix("[") {
            if let close = remoteAddress.firstIndex(of: "]") {
                return String(remoteAddress[remoteAddress.index(after: remoteAddress.startIndex)..<close])
            }
            return remoteAddress
        }
        if let colon = remoteAddress.lastIndex(of: ":") {
            return String(remoteAddress[..<colon])
        }
        return remoteAddress
    }

    /// Fan-out grouping key for a local endpoint: the parsed port when the
    /// endpoint is `host:port` / `[v6]:port`, otherwise the raw string so
    /// Unix-ish or unparseable endpoints still group deterministically
    /// instead of being dropped. Plain `String` on purpose — tuples can't be
    /// dictionary keys, and a struct would be ceremony for one label.
    /// `Int(label)` recovers the port for display; nil means "not a port".
    private static func localPortLabel(for localAddress: String) -> String {
        if localAddress.hasPrefix("[") {
            // "[::1]:8080" — port follows "]:"
            if let range = localAddress.range(of: "]:"),
               Int(localAddress[range.upperBound...]) != nil {
                return String(localAddress[range.upperBound...])
            }
            return localAddress
        }
        if let colon = localAddress.lastIndex(of: ":") {
            let tail = String(localAddress[localAddress.index(after: colon)...])
            if Int(tail) != nil { return tail }
        }
        return localAddress
    }
}
