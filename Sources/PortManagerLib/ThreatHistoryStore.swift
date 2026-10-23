// ThreatHistoryStore.swift — Persisted forensic trail for threat findings.
//
// Why this exists:
//   Detection without memory can't answer "when did this bot first appear?"
//   The live assessment shows NOW; this store keeps the last N findings with
//   timestamps so the Security Center can show recency ("3rd sighting in
//   2 days") and operators can reconstruct an incident after the fact.
//
// Design:
//   - Append-only ring capped at `maxFindings` (default 200). Oldest drops
//     first; the file never grows without bound on a busy machine.
//   - NSLock-guarded synchronous API. Call from any thread; persistence
//     writes are small JSON encodes and stay off hot paths (callers record
//     once per assessment, not once per connection).
//   - Injectable directory so tests point at a temp dir instead of the real
//     `~/.portpilot`. Production default is `~/.portpilot/threat-history.json`.
//   - Corrupt files decode to empty (logged nowhere — this is a cache, not
//     source of truth; the next assessment repopulates it).
//
// Expansion:
//   - Per-finding resolution state (acknowledged / allowlisted / blocked)
//     attaches as new optional fields on a wrapper type — don't mutate
//     ThreatFinding for UI state; wrap it.

import Foundation

/// Thread-safe capped ring of past threat findings, persisted as JSON.
public final class ThreatHistoryStore: @unchecked Sendable {

    /// Hard cap on retained findings. Oldest-first eviction keeps the file
    /// small and the Security Center's "recent" query instant.
    public let maxFindings: Int

    private let fileURL: URL
    private let ownsDirectoryPermissions: Bool
    private let lock = NSLock()
    private var cached: [ThreatFinding]

    /// - Parameter directory: Folder holding `threat-history.json`. Defaults
    ///   to `~/.portpilot`. Tests MUST pass a temp directory.
    public init(directory: URL? = nil, maxFindings: Int = 200) {
        let dir = directory ?? ThreatHistoryStore.defaultDirectory()
        self.fileURL = dir.appendingPathComponent("threat-history.json")
        self.ownsDirectoryPermissions = directory == nil
        self.maxFindings = maxFindings
        try? SecureFilePermissions.ensurePrivateDirectory(
            dir,
            secureExisting: ownsDirectoryPermissions
        )
        SecureFilePermissions.repairPrivateFileIfPresent(fileURL)
        self.cached = Self.load(from: fileURL)
    }

    /// Production home for threat persistence, shared with the blocklist.
    public static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".portpilot")
    }

    /// All retained findings, newest first.
    public func recent(limit: Int? = nil) -> [ThreatFinding] {
        lock.lock()
        defer { lock.unlock() }
        let sorted = cached.sorted { $0.detectedAt > $1.detectedAt }
        guard let limit else { return sorted }
        return Array(sorted.prefix(limit))
    }

    /// Append findings from one assessment and persist. Empty arrays are a
    /// no-op (no file churn on clean polls).
    public func record(_ findings: [ThreatFinding]) {
        guard !findings.isEmpty else { return }
        lock.lock()
        cached.append(contentsOf: findings)
        if cached.count > maxFindings {
            cached.removeFirst(cached.count - maxFindings)
        }
        let snapshot = cached
        lock.unlock()
        persist(snapshot)
    }

    /// How many times this (process, signals) shape was seen before — backs
    /// the "3rd sighting" affordance in the Security Center.
    public func sightingCount(for finding: ThreatFinding) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let shape = Set(finding.signals.map { $0.type })
        return cached.filter {
            $0.processName == finding.processName && Set($0.signals.map { $0.type }) == shape
        }.count
    }

    /// Wipe memory and disk. Used by "Clear history" and tests.
    public func clear() {
        lock.lock()
        cached = []
        lock.unlock()
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Private persistence

    private static func load(from url: URL) -> [ThreatFinding] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ThreatFinding].self, from: data)) ?? []
    }

    private func persist(_ findings: [ThreatFinding]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(findings) else { return }
        do {
            try SecureFilePermissions.writePrivateData(
                data,
                to: fileURL,
                secureExistingDirectory: ownsDirectoryPermissions
            )
        } catch {
            // Threat history is a cache, not source of truth. A failed secure
            // write must never fall back to a more permissive file.
            return
        }
    }
}
