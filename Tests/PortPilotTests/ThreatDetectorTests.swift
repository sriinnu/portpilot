// ThreatDetectorTests.swift — Pure unit tests for the threat engine.
//
// Contract: fabricated snapshots only. No lsof/ss, no home-directory I/O,
// no clock dependence. Blocklist matching is stubbed via the injected
// closure; BlocklistStore's real file I/O is tested with a temp directory.

import XCTest
@testable import PortManagerLib

final class ThreatDetectorTests: XCTestCase {

    // MARK: - Helpers

    private func conn(
        pid: Int,
        process: String,
        remote: String,
        local: String = "192.168.1.10:8080",
        user: String = "sriinnu",
        executablePath: String? = nil
    ) -> EstablishedConnection {
        EstablishedConnection(
            localAddress: local,
            remoteAddress: remote,
            state: "ESTABLISHED",
            pid: pid,
            processName: process,
            user: user,
            executablePath: executablePath ?? "/Applications/\(process)"
        )
    }

    private func many(pid: Int, process: String, count: Int, remoteBase: String = "10.0.0") -> [EstablishedConnection] {
        (0..<count).map { i in
            conn(pid: pid, process: process, remote: "\(remoteBase).\(i % 250):443")
        }
    }

    private var denyAll: (EstablishedConnection) -> Bool { { _ in false } }

    // MARK: - Clean snapshots stay clean

    func testEmptySnapshotIsClean() {
        let assessment = ThreatDetector.assess(connections: [], isBlocklisted: denyAll)
        XCTAssertTrue(assessment.isClean)
        XCTAssertNil(assessment.highestSeverity)
    }

    func testSmallBenignSnapshotIsCleanOnColdStart() {
        // Cold start (unseeded baseline): counts under threshold, no
        // blocklist hits — even unknown processes stay quiet.
        let conns = many(pid: 100, process: "myapp", count: 4)
        let assessment = ThreatDetector.assess(connections: conns, isBlocklisted: denyAll)
        XCTAssertTrue(assessment.isClean)
    }

    // MARK: - Rule 1: blocklisted remote (critical)

    func testBlocklistedRemoteFiresCritical() {
        let conns = [
            conn(pid: 200, process: "evil-miner", remote: "203.0.113.9:3333"),
            conn(pid: 200, process: "evil-miner", remote: "198.51.100.7:80"),
        ]
        let assessment = ThreatDetector.assess(
            connections: conns,
            isBlocklisted: { $0.remoteAddress.hasPrefix("203.0.113.9") }
        )
        XCTAssertEqual(assessment.findings.count, 1)
        XCTAssertEqual(assessment.highestSeverity, .critical)
        let signal = assessment.findings[0].signals.first { $0.type == .blocklistedRemote }
        XCTAssertNotNil(signal)
        XCTAssertEqual(signal?.count, 1)
    }

    // MARK: - Rule 2: high connection count (warning, default >50)

    func testHighConnectionCountFiresOverThreshold() {
        let assessment = ThreatDetector.assess(
            connections: many(pid: 300, process: "browser", count: 51),
            isBlocklisted: denyAll
        )
        let signal = assessment.findings.first?.signals.first { $0.type == .highConnectionCount }
        XCTAssertNotNil(signal)
        XCTAssertEqual(assessment.highestSeverity, .warning)
    }

    func testHighConnectionCountQuietAtThreshold() {
        // Same-remote connections isolate rule 2: 50 distinct remotes would
        // (correctly) trip the fan-out rule instead.
        let conns = (0..<50).map { _ in conn(pid: 300, process: "browser", remote: "93.184.216.34:443") }
        let assessment = ThreatDetector.assess(connections: conns, isBlocklisted: denyAll)
        XCTAssertTrue(assessment.isClean)
    }

    func testHighConnectionThresholdIsConfigurable() {
        var config = ThreatConfiguration.default
        config.highConnectionThreshold = 100
        let conns = (0..<90).map { _ in conn(pid: 300, process: "browser", remote: "93.184.216.34:443") }
        let assessment = ThreatDetector.assess(
            connections: conns,
            isBlocklisted: denyAll,
            configuration: config
        )
        XCTAssertTrue(assessment.isClean)
    }

    func testDisabledRuleStaysQuiet() {
        var config = ThreatConfiguration.default
        config.disabledSignals = [ThreatSignalType.highConnectionCount.rawValue]
        let assessment = ThreatDetector.assess(
            connections: many(pid: 300, process: "browser", count: 200),
            isBlocklisted: denyAll,
            configuration: config
        )
        // 200 conns to 200 distinct remotes on one port also trips fan-out;
        // disable that too to isolate this rule's kill switch.
        let nonFanout = assessment.findings.flatMap { $0.signals }.filter { $0.type == .highConnectionCount }
        XCTAssertTrue(nonFanout.isEmpty)
    }

    // MARK: - Rule 3: remote fan-out

    func testRemoteFanoutFiresOnDistinctRemotes() {
        // 15 distinct remotes on :8080 — scan/knock shape, even though the
        // total count (15) is far below the high-count threshold.
        let conns = (0..<15).map { i in
            conn(pid: 400, process: "api", remote: "198.51.100.\(i):\(40000 + i)")
        }
        let assessment = ThreatDetector.assess(connections: conns, isBlocklisted: denyAll)
        let signal = assessment.findings.first?.signals.first { $0.type == .remoteFanout }
        XCTAssertNotNil(signal)
        XCTAssertEqual(signal?.localPort, 8080)
    }

    // MARK: - Rules 4–5: baseline-relative (seeded only)

    func testBaselineRulesSkippedWhenUnseeded() {
        // A brand-new process with 30 connections: cold start must not page.
        let conns = many(pid: 500, process: "fresh-binary", count: 30)
        let assessment = ThreatDetector.assess(
            connections: conns,
            isBlocklisted: denyAll,
            baseline: ThreatBaseline()
        )
        XCTAssertTrue(assessment.findings.flatMap { $0.signals }.filter {
            $0.type == .firstSeenDialer || $0.type == .newRemoteBurst
        }.isEmpty)
    }

    func testFirstSeenDialerFiresForUnknownProcess() {
        var baseline = ThreatBaseline()
        let safari = conn(pid: 499, process: "safari", remote: "93.184.216.34:443")
        baseline.advanceSnapshot([safari])
        baseline.advanceSnapshot([safari])
        let conns = many(pid: 500, process: "fresh-binary", count: 6)
        let assessment = ThreatDetector.assess(connections: conns, isBlocklisted: denyAll, baseline: baseline)
        XCTAssertNotNil(assessment.findings.first?.signals.first { $0.type == .firstSeenDialer })
    }

    func testNewRemoteBurstFiresForKnownProcess() {
        var baseline = ThreatBaseline()
        let known = conn(pid: 600, process: "api", remote: "10.0.0.1:443")
        baseline.advanceSnapshot([known])
        baseline.advanceSnapshot([known])
        let conns = (0..<12).map { i in
            conn(pid: 600, process: "api", remote: "203.0.113.\(i):443")
        }
        let assessment = ThreatDetector.assess(connections: conns, isBlocklisted: denyAll, baseline: baseline)
        XCTAssertNotNil(assessment.findings.first?.signals.first { $0.type == .newRemoteBurst })
    }

    func testKnownRemotesDoNotBurst() {
        var baseline = ThreatBaseline()
        let conns = (0..<12).map { i in
            conn(pid: 600, process: "api", remote: "203.0.113.\(i):443")
        }
        baseline.advanceSnapshot(conns)
        baseline.advanceSnapshot(conns)
        let assessment = ThreatDetector.assess(connections: conns, isBlocklisted: denyAll, baseline: baseline)
        XCTAssertTrue(assessment.findings.flatMap { $0.signals }.filter { $0.type == .newRemoteBurst }.isEmpty)
    }

    func testOneNoisySnapshotDoesNotBecomeTrusted() {
        var baseline = ThreatBaseline()
        let noisy = many(pid: 610, process: "noisy", count: 100)
        baseline.advanceSnapshot(noisy)
        XCTAssertFalse(baseline.contains(noisy[0]))
        baseline.advanceSnapshot(noisy)
        XCTAssertTrue(baseline.contains(noisy[0]))
    }

    func testEmptySnapshotInitializesBaseline() {
        var baseline = ThreatBaseline()
        baseline.advanceSnapshot([])
        XCTAssertTrue(baseline.isSeeded)

        let later = many(pid: 620, process: "later", count: 6)
        let assessment = ThreatDetector.assess(connections: later, isBlocklisted: denyAll, baseline: baseline)
        XCTAssertNotNil(assessment.findings.flatMap(\.signals).first { $0.type == .firstSeenDialer })
    }

    func testIdentityPromotionDoesNotTrustOneOffRemotes() {
        var baseline = ThreatBaseline()
        let first = conn(pid: 625, process: "api", remote: "192.0.2.1:443")
        let second = conn(pid: 625, process: "api", remote: "192.0.2.2:443")
        baseline.advanceSnapshot([first])
        baseline.advanceSnapshot([second])

        XCTAssertTrue(baseline.contains(second))
        XCTAssertEqual(baseline.unseenRemotes(for: second, remotes: ["192.0.2.1", "192.0.2.2"]),
                       ["192.0.2.1", "192.0.2.2"])

        baseline.advanceSnapshot([second])
        XCTAssertTrue(baseline.unseenRemotes(for: second, remotes: ["192.0.2.2"]).isEmpty)
        XCTAssertEqual(baseline.unseenRemotes(for: first, remotes: ["192.0.2.1"]), ["192.0.2.1"])
    }

    func testInterruptedRemoteCandidateMustRecurAgain() {
        var baseline = ThreatBaseline()
        let connection = conn(pid: 626, process: "api", remote: "192.0.2.3:443")
        baseline.advanceSnapshot([connection])
        baseline.advanceSnapshot([])
        baseline.advanceSnapshot([connection])
        XCTAssertFalse(baseline.contains(connection))
        XCTAssertEqual(baseline.unseenRemotes(for: connection, remotes: ["192.0.2.3"]), ["192.0.2.3"])
        baseline.advanceSnapshot([connection])
        XCTAssertTrue(baseline.unseenRemotes(for: connection, remotes: ["192.0.2.3"]).isEmpty)
    }

    func testSameNameDifferentExecutableDoesNotInheritTrust() {
        var baseline = ThreatBaseline()
        let trusted = conn(pid: 630, process: "helper", remote: "10.0.0.1:443", executablePath: "/Applications/Trusted/helper")
        baseline.advanceSnapshot([trusted])
        baseline.advanceSnapshot([trusted])

        let replacement = (0..<6).map { index in
            conn(pid: 631, process: "helper", remote: "198.51.100.\(index):443", executablePath: "/tmp/helper")
        }
        let assessment = ThreatDetector.assess(connections: replacement, isBlocklisted: denyAll, baseline: baseline)
        XCTAssertNotNil(assessment.findings.flatMap(\.signals).first { $0.type == .firstSeenDialer })
    }

    // MARK: - Assessment ordering

    func testFindingsSortCriticalFirst() {
        let bad = conn(pid: 700, process: "aaa-miner", remote: "203.0.113.9:3333")
        let noisy = many(pid: 701, process: "zzz-browser", count: 60)
        let assessment = ThreatDetector.assess(
            connections: [bad] + noisy,
            isBlocklisted: { $0.remoteAddress.hasPrefix("203.0.113.9") }
        )
        XCTAssertEqual(assessment.findings.first?.processName, "aaa-miner")
    }

    // MARK: - Address parsing

    func testRemoteHostStripsPortAndBrackets() {
        XCTAssertEqual(ThreatDetector.remoteHost(from: "10.0.0.5:443"), "10.0.0.5")
        XCTAssertEqual(ThreatDetector.remoteHost(from: "[2001:db8::1]:443"), "2001:db8::1")
        XCTAssertEqual(ThreatDetector.remoteHost(from: "example.com:80"), "example.com")
    }

    // MARK: - BlocklistStore (temp-dir file I/O)

    func testBlocklistStoreAddRemoveRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = BlocklistStore(path: dir.appendingPathComponent("blocklist.txt").path)
        XCTAssertTrue(try store.add("evil.example"))
        XCTAssertFalse(try store.add("EVIL.example")) // dup, case-insensitive
        XCTAssertEqual(store.entries(), ["evil.example"])
        XCTAssertTrue(try store.remove("evil.EXAMPLE"))
        XCTAssertEqual(store.entries(), [])
    }

    func testBlocklistStoreRejectsGarbage() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = BlocklistStore(path: dir.appendingPathComponent("blocklist.txt").path)
        XCTAssertThrowsError(try store.add("has space"))
        XCTAssertThrowsError(try store.add("   "))
        XCTAssertThrowsError(try store.add("."))
    }

    func testThreatHistoryCapsAndCountsSightings() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let history = ThreatHistoryStore(directory: dir, maxFindings: 3)
        let finding = ThreatFinding(
            processName: "miner", pid: 1, user: "x",
            signals: [ThreatSignal(type: .highConnectionCount, severity: .warning, processName: "miner", pid: 1, summary: "s", remoteSample: "r", count: 60)]
        )
        history.record([finding, finding, finding, finding])
        XCTAssertEqual(history.recent().count, 3)
        XCTAssertEqual(history.sightingCount(for: finding), 3)
    }

    func testSecurityPersistenceUsesPrivatePermissions() throws {
        #if !os(Windows)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let blocklistURL = root.appendingPathComponent("blocklist/blocklist.txt")
        XCTAssertTrue(try BlocklistStore(path: blocklistURL.path).add("evil.example"))

        let historyDirectory = root.appendingPathComponent("history")
        let history = ThreatHistoryStore(directory: historyDirectory, maxFindings: 3)
        let finding = ThreatFinding(
            processName: "fixture", pid: 42, user: "tester",
            signals: [ThreatSignal(type: .firstSeenDialer, severity: .info, processName: "fixture", pid: 42, summary: "fixture", remoteSample: "127.0.0.1:9", count: 1)]
        )
        history.record([finding])

        XCTAssertEqual(permissions(of: blocklistURL.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(permissions(of: blocklistURL), 0o600)
        XCTAssertEqual(permissions(of: historyDirectory), 0o700)
        XCTAssertEqual(permissions(of: historyDirectory.appendingPathComponent("threat-history.json")), 0o600)
        #endif
    }

    func testExistingSensitiveFilesAreRepairedWithoutChmoddingCustomParent() throws {
        #if !os(Windows)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)

        let blocklist = root.appendingPathComponent("blocklist.txt")
        try Data("evil.example\n".utf8).write(to: blocklist)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: blocklist.path)
        _ = BlocklistStore(path: blocklist.path)

        let history = root.appendingPathComponent("threat-history.json")
        try Data("[]".utf8).write(to: history)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: history.path)
        _ = ThreatHistoryStore(directory: root)

        let cronHistory = root.appendingPathComponent("cron_run_history.json")
        try Data("{}".utf8).write(to: cronHistory)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: cronHistory.path)
        _ = CronRunManager(directory: root)

        XCTAssertEqual(permissions(of: root), 0o755)
        XCTAssertEqual(permissions(of: blocklist), 0o600)
        XCTAssertEqual(permissions(of: history), 0o600)
        XCTAssertEqual(permissions(of: cronHistory), 0o600)
        #endif
    }

    func testSecureCrontabTemporaryFileIsPrivate() throws {
        #if !os(Windows)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = try PortManager.writeSecureTemporaryCrontab("* * * * * echo safe\n", baseDirectory: root)
        XCTAssertEqual(permissions(of: file.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(permissions(of: file), 0o600)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "* * * * * echo safe\n")
        #endif
    }

    func testBoundedOutputBufferCapsRetainedBytes() {
        var buffer = BoundedOutputBuffer(limit: 4)
        buffer.append(Data("abc".utf8))
        buffer.append(Data("def".utf8))
        XCTAssertEqual(String(data: buffer.data, encoding: .utf8), "abcd")
        XCTAssertTrue(buffer.wasTruncated)
    }

    func testCronRunNowEnforcesRuntimeLimitAndSecuresHistory() throws {
        #if !os(Windows)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = CronRunManager(directory: root, maxRuntime: 1)
        let job = CronjobEntry(command: "sleep 30", schedule: "manual", source: "test")
        XCTAssertTrue(manager.runNow(job: job))

        let deadline = Date().addingTimeInterval(6)
        while manager.isRunning(job.id), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }

        XCTAssertFalse(manager.isRunning(job.id))
        XCTAssertEqual(manager.record(for: job.id).runCount, 1)
        XCTAssertEqual(permissions(of: root.appendingPathComponent("cron_run_history.json")), 0o600)
        #endif
    }

    func testCheckedCommandRejectsTruncatedOutput() throws {
        #if !os(Windows)
        XCTAssertThrowsError(
            try PortManager().runCommand("/bin/sh", arguments: ["-c", "printf 12345"], maxOutputBytes: 4)
        ) { error in
            guard case PortManagerError.commandOutputTruncated(_, 4) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        #endif
    }

    #if !os(Windows)
    private func permissions(of url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
    #endif
}
