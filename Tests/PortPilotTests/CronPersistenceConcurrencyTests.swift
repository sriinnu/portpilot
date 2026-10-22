import XCTest
@testable import PortManagerLib

final class CronPersistenceConcurrencyTests: XCTestCase {
    func testCronEditTargetsExactDuplicateOccurrence() throws {
        let manager = PortManager()
        let original = """
        0 9 * * * /usr/bin/backup
        0 9 * * * /usr/bin/backup
        """
        let jobs = manager.parseCrontab(
            output: original,
            source: "user",
            user: "tester",
            hasUserColumn: false
        )
        XCTAssertEqual(jobs.count, 2)
        XCTAssertTrue(jobs[1].id.hasSuffix("#2"))

        let updated = try manager.rewrittenCrontab(original, job: jobs[1], paused: true)
        let lines = updated.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(lines[0], "0 9 * * * /usr/bin/backup")
        XCTAssertEqual(lines[1], "#PORTPILOT_PAUSED# 0 9 * * * /usr/bin/backup")
    }

    func testIncompleteCrontabReadsAbortTransactionWithoutInstall() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = PortManager()
        let original = "0 9 * * * /usr/bin/backup\n"
        let job = try XCTUnwrap(manager.parseCrontab(
            output: original, source: "user", user: "tester", hasUserColumn: false
        ).first)
        let cases = [
            PortManager.CommandOutput(output: "0 9 * * * backup\n", exitStatus: nil, timedOut: true, outputTruncated: false),
            PortManager.CommandOutput(output: "0 9 * * * backup\n", exitStatus: 0, timedOut: false, outputTruncated: true),
            PortManager.CommandOutput(output: "partial", exitStatus: 2, timedOut: false, outputTruncated: false),
            PortManager.CommandOutput(output: "", exitStatus: nil, timedOut: false, outputTruncated: false),
        ]

        for result in cases {
            var installed = false
            let io = CrontabControlIO(
                read: { try PortManager.checkedCrontabRead(result) },
                install: { _ in installed = true }
            )

            XCTAssertThrowsError(try manager.performCronEdit(
                job: job,
                paused: true,
                lockURL: root.appendingPathComponent("cron.lock"),
                io: io
            ))
            XCTAssertFalse(installed)
        }
    }

    func testChangedCrontabAbortsWithoutInstall() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = PortManager()
        let original = "0 9 * * * /usr/bin/backup\n"
        let changed = original + "15 10 * * * /usr/bin/new-job\n"
        let job = try XCTUnwrap(manager.parseCrontab(
            output: original, source: "user", user: "tester", hasUserColumn: false
        ).first)
        var reads = [original, changed]
        var installed = false
        let io = CrontabControlIO(
            read: { reads.removeFirst() },
            install: { _ in installed = true }
        )

        XCTAssertThrowsError(try manager.performCronEdit(
            job: job,
            paused: true,
            lockURL: root.appendingPathComponent("cron.lock"),
            io: io
        )) { error in
            guard case PortManager.CronControlError.changedDuringEdit = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertFalse(installed)
    }

    func testConcurrentPortPilotCronEditsSerializeWithoutLostUpdate() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = PortManager()
        let original = """
        0 9 * * * /usr/bin/backup
        15 10 * * * /usr/bin/cleanup
        """
        let jobs = manager.parseCrontab(
            output: original,
            source: "user",
            user: "tester",
            hasUserColumn: false
        )
        XCTAssertEqual(jobs.count, 2)

        let fixture = LockedCrontab(original)
        let failures = LockedFailures()
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            do {
                try manager.performCronEdit(
                    job: jobs[index],
                    paused: true,
                    lockURL: root.appendingPathComponent("cron.lock"),
                    io: fixture.io
                )
            } catch {
                failures.append(error)
            }
        }

        XCTAssertTrue(failures.values.isEmpty, "Unexpected edit failures: \(failures.values)")
        XCTAssertTrue(fixture.content.contains("#PORTPILOT_PAUSED# 0 9 * * * /usr/bin/backup"))
        XCTAssertTrue(fixture.content.contains("#PORTPILOT_PAUSED# 15 10 * * * /usr/bin/cleanup"))
    }

    func testConcurrentBlocklistStoresDoNotLoseUpdates() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("blocklist.txt").path
        let failures = LockedFailures()

        DispatchQueue.concurrentPerform(iterations: 32) { index in
            do {
                _ = try BlocklistStore(path: path).add("host-\(index).example")
            } catch {
                failures.append(error)
            }
        }

        XCTAssertTrue(failures.values.isEmpty, "Unexpected edit failures: \(failures.values)")
        XCTAssertEqual(Set(BlocklistStore(path: path).entries()).count, 32)
        #if !os(Windows)
        let lockURL = root.appendingPathComponent(".blocklist.txt.lock")
        let attrs = try FileManager.default.attributesOfItem(atPath: lockURL.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        #endif
    }

    func testBlocklistMutationRefusesInvalidExistingFileWithoutOverwrite() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("blocklist.txt")
        let original = Data([0xFF, 0xFE, 0x00, 0x73, 0x65, 0x6E, 0x74, 0x69, 0x6E, 0x65, 0x6C])
        try original.write(to: fileURL)
        let store = BlocklistStore(path: fileURL.path)

        XCTAssertThrowsError(try store.add("new.example")) { error in
            guard case BlocklistError.ioError = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), original)
    }

    func testIndependentCronStopCarriesObservedIdentityAcrossRecheck() throws {
        let manager = PortManager()
        let expected = processIdentity(pid: 401, token: "original")
        var snapshots = [[401], [401]]
        var terminated: [ProcessIdentity] = []
        let io = CronProcessControlIO(
            matchingPIDs: { _ in snapshots.removeFirst() },
            identities: { _ in [401: expected] },
            terminate: { identities, _ in
                terminated = identities
                return ProcessTerminationResult(outcomes: [401: .terminated])
            }
        )

        let result = try XCTUnwrap(manager.stopRunningProcessesResult(
            matching: "/usr/bin/backup",
            io: io
        ))

        XCTAssertEqual(terminated, [expected])
        XCTAssertTrue(result.isComplete)
    }

    func testIndependentCronStopRefusesNewUnboundMatch() throws {
        let manager = PortManager()
        let expected = processIdentity(pid: 402, token: "original")
        var snapshots = [[402], [402, 403]]
        var terminated: [ProcessIdentity] = []
        let io = CronProcessControlIO(
            matchingPIDs: { _ in snapshots.removeFirst() },
            identities: { _ in [402: expected] },
            terminate: { identities, _ in
                terminated = identities
                return ProcessTerminationResult(outcomes: [402: .terminated])
            }
        )

        let result = try XCTUnwrap(manager.stopRunningProcessesResult(
            matching: "/usr/bin/backup",
            io: io
        ))

        XCTAssertEqual(terminated, [expected])
        XCTAssertEqual(result.outcomes[403], .identityUnavailable)
        XCTAssertFalse(result.isComplete)
    }

    func testTrackedCronStopRefusesChangedRootBeforeSignal() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let expected = processIdentity(pid: 501, token: "original")
        let replacement = processIdentity(pid: 501, token: "replacement")
        var rootReads = 0
        var didTerminate = false
        let manager = CronRunManager(
            directory: root,
            childPIDProvider: { _ in [] },
            identityProvider: { pids in
                if pids == [501] {
                    rootReads += 1
                    return [501: rootReads == 1 ? expected : replacement]
                }
                return Dictionary(uniqueKeysWithValues: pids.map { ($0, expected) })
            },
            identityTerminator: { _, _, _ in
                didTerminate = true
                return ProcessTerminationResult(outcomes: [:])
            }
        )

        let result = try manager.terminateTracked(rootIdentity: expected)

        XCTAssertEqual(result.outcomes[501], .identityMismatch)
        XCTAssertFalse(didTerminate)
    }

    func testTrackedCronStopDoesNotSignalDescendantRemovedDuringCapture() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let rootIdentity = processIdentity(pid: 601, token: "root")
        let childIdentity = processIdentity(pid: 602, token: "child")
        var rootTreeReads = 0
        var terminated: [ProcessIdentity] = []
        let manager = CronRunManager(
            directory: root,
            childPIDProvider: { pid in
                guard pid == 601 else { return [] }
                rootTreeReads += 1
                return rootTreeReads == 1 ? [602] : []
            },
            identityProvider: { pids in
                var result: [Int: ProcessIdentity] = [:]
                if pids.contains(601) { result[601] = rootIdentity }
                if pids.contains(602) { result[602] = childIdentity }
                return result
            },
            identityTerminator: { identities, _, _ in
                terminated = identities
                return ProcessTerminationResult(outcomes: [601: .terminated])
            }
        )

        let result = try manager.terminateTracked(rootIdentity: rootIdentity)

        XCTAssertEqual(terminated, [rootIdentity])
        XCTAssertEqual(result.outcomes[602], .identityUnavailable)
        XCTAssertFalse(result.isComplete)
    }

    func testTrackedCronStopAllowsExecPathChangeForSameIncarnation() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let expected = processIdentity(pid: 701, token: "same", path: nil)
        let afterExec = processIdentity(pid: 701, token: "same", path: "/usr/bin/sleep")
        var terminated: [ProcessIdentity] = []
        let manager = CronRunManager(
            directory: root,
            childPIDProvider: { _ in [] },
            identityProvider: { _ in [701: afterExec] },
            identityTerminator: { identities, _, _ in
                terminated = identities
                return ProcessTerminationResult(outcomes: [701: .terminated])
            }
        )

        let result = try manager.terminateTracked(rootIdentity: expected)

        XCTAssertEqual(terminated, [expected])
        XCTAssertTrue(result.isComplete)
    }

    func testCronStopSummaryNeverTreatsUnresolvedPidsAsSuccess() {
        let tracked = ProcessTerminationResult(outcomes: [101: .terminated, 102: .survived])
        let independent = ProcessTerminationResult(outcomes: [103: .permissionDenied])
        let summary = CronStopSummary(results: [tracked, independent])

        XCTAssertTrue(summary.attempted)
        XCTAssertEqual(summary.stopped, [101])
        XCTAssertEqual(summary.unresolved, [102, 103])
        XCTAssertFalse(summary.isComplete)
    }

    func testCronStopSummaryDistinguishesNotRunningFromComplete() {
        XCTAssertFalse(CronStopSummary(results: [nil, nil]).attempted)
        XCTAssertFalse(CronStopSummary(results: [nil, nil]).isComplete)

        let complete = CronStopSummary(results: [
            ProcessTerminationResult(outcomes: [201: .terminated, 202: .alreadyExited]),
            nil,
        ])
        XCTAssertTrue(complete.isComplete)
        XCTAssertEqual(complete.stopped, [201, 202])
        XCTAssertTrue(complete.unresolved.isEmpty)
    }

    func testCronStopSummaryTreatsDiscoveryFailureAsUnknown() {
        let tracked = ProcessTerminationResult(outcomes: [301: .terminated])
        let summary = CronStopSummary(
            results: [tracked],
            errors: ["process discovery failed"]
        )
        XCTAssertTrue(summary.attempted)
        XCTAssertEqual(summary.stopped, [301])
        XCTAssertFalse(summary.isComplete)
        XCTAssertEqual(summary.errors, ["process discovery failed"])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func processIdentity(
        pid: Int,
        token: String,
        path: String? = nil
    ) -> ProcessIdentity {
        ProcessIdentity(
            pid: pid,
            startTime: Date(timeIntervalSince1970: TimeInterval(pid)),
            incarnationToken: token,
            executablePath: path,
            user: "tester"
        )
    }
}

private final class LockedFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Error] = []

    var values: [Error] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ error: Error) {
        lock.lock()
        storage.append(error)
        lock.unlock()
    }
}

private final class LockedCrontab: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: String

    init(_ content: String) {
        storage = content
    }

    var content: String {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var io: CrontabControlIO {
        CrontabControlIO(
            read: { [self] in self.content },
            install: { [self] updated in
                self.lock.lock()
                self.storage = updated
                self.lock.unlock()
            }
        )
    }
}
