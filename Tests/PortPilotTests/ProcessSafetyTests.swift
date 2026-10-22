import XCTest
@testable import PortManagerLib
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Injected syscall tests only. These never inspect or signal a real process.
final class ProcessSafetyTests: XCTestCase {
    private let expected = ProcessIdentity(
        pid: 42,
        startTime: Date(timeIntervalSince1970: 100),
        incarnationToken: "incarnation-a",
        executablePath: "/tmp/a",
        user: "tester"
    )

    func testPermissionDeniedProbeMeansAliveAndNeverReportsSuccess() {
        var sentSignals: [Int32] = []
        let core = ProcessSignalCore(environment: ProcessSignalEnvironment(
            signal: { _, signal in
                sentSignals.append(signal)
                return .failed(errno: EPERM)
            },
            probe: { _ in .permissionDenied },
            identity: { _ in self.expected },
            wait: { _ in }
        ))

        let result = core.terminate(
            [ProcessTerminationTarget(pid: 42, expectedIdentity: expected)],
            force: false,
            timeout: 0
        )

        XCTAssertEqual(sentSignals, [SIGTERM])
        XCTAssertEqual(result.outcomes[42], .permissionDenied)
        XCTAssertEqual(result.survivors, [42])
        XCTAssertFalse(result.isComplete)
    }

    func testProtectedAndInvalidPIDsAreRejectedWithoutSyscalls() {
        var signalCount = 0
        let core = ProcessSignalCore(environment: ProcessSignalEnvironment(
            signal: { _, _ in signalCount += 1; return .success },
            probe: { _ in .running },
            identity: { _ in self.expected },
            wait: { _ in }
        ))

        let result = core.terminate(
            [
                ProcessTerminationTarget(pid: 1, expectedIdentity: expected),
                ProcessTerminationTarget(pid: 0, expectedIdentity: expected),
                ProcessTerminationTarget(pid: -1, expectedIdentity: expected),
            ],
            force: true,
            timeout: 0
        )

        XCTAssertEqual(signalCount, 0)
        XCTAssertEqual(result.invalid, [-1, 0, 1])
        XCTAssertFalse(result.isComplete)
    }

    func testStaleIdentityFailsClosedWithoutSignal() {
        var signalCount = 0
        let replacement = ProcessIdentity(
            pid: expected.pid,
            startTime: expected.startTime,
            incarnationToken: "incarnation-b",
            executablePath: expected.executablePath,
            user: expected.user
        )
        let core = ProcessSignalCore(environment: ProcessSignalEnvironment(
            signal: { _, _ in signalCount += 1; return .success },
            probe: { _ in .running },
            identity: { _ in replacement },
            wait: { _ in }
        ))

        let result = core.terminate(
            [ProcessTerminationTarget(pid: expected.pid, expectedIdentity: expected)],
            force: false,
            timeout: 0
        )

        XCTAssertEqual(signalCount, 0)
        XCTAssertEqual(result.outcomes[expected.pid], .identityMismatch)
    }

    func testIdentityIsRecheckedBeforeKillEscalation() {
        var identityReads = 0
        var sentSignals: [Int32] = []
        let replacement = ProcessIdentity(
            pid: expected.pid,
            startTime: expected.startTime,
            incarnationToken: "replacement",
            executablePath: expected.executablePath,
            user: expected.user
        )
        let core = ProcessSignalCore(environment: ProcessSignalEnvironment(
            signal: { _, signal in sentSignals.append(signal); return .success },
            probe: { _ in .running },
            identity: { _ in
                identityReads += 1
                return identityReads == 1 ? self.expected : replacement
            },
            wait: { _ in }
        ))

        let result = core.terminate(
            [ProcessTerminationTarget(pid: expected.pid, expectedIdentity: expected)],
            force: false,
            timeout: 0
        )

        XCTAssertEqual(sentSignals, [SIGTERM])
        XCTAssertEqual(result.outcomes[expected.pid], .identityMismatch)
    }

    func testUnknownIdentityRefusesControlSignal() {
        var signalCount = 0
        let core = ProcessSignalCore(environment: ProcessSignalEnvironment(
            signal: { _, _ in signalCount += 1; return .success },
            probe: { _ in .running },
            identity: { _ in nil },
            wait: { _ in }
        ))

        XCTAssertEqual(core.send(.pause, to: expected), .identityUnavailable)
        XCTAssertEqual(signalCount, 0)
    }

    func testConfirmedExitProducesTruthfulReceipt() {
        var probes = 0
        let core = ProcessSignalCore(environment: ProcessSignalEnvironment(
            signal: { _, _ in .success },
            probe: { _ in
                probes += 1
                return probes == 1 ? .running : .notFound
            },
            identity: { _ in self.expected },
            wait: { _ in }
        ))

        let result = core.terminate(
            [ProcessTerminationTarget(pid: 42, expectedIdentity: expected)],
            force: false,
            timeout: 0.1
        )

        XCTAssertEqual(result.terminated, [42])
        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.unresolved.isEmpty)
    }

    func testCancellationAfterTermPreventsKillEscalation() {
        var continueChecks = 0
        var sentSignals: [Int32] = []
        let core = ProcessSignalCore(environment: ProcessSignalEnvironment(
            signal: { _, signal in sentSignals.append(signal); return .success },
            probe: { _ in .running },
            identity: { _ in self.expected },
            wait: { _ in }
        ))

        let result = core.terminate(
            [ProcessTerminationTarget(pid: expected.pid, expectedIdentity: expected)],
            force: false,
            timeout: 1,
            shouldContinue: {
                continueChecks += 1
                return continueChecks == 1
            }
        )

        XCTAssertEqual(sentSignals, [SIGTERM])
        XCTAssertEqual(result.outcomes[expected.pid], .cancelled)
        XCTAssertEqual(result.cancelled, [expected.pid])
        XCTAssertEqual(result.unresolved, [expected.pid])
        XCTAssertFalse(result.isComplete)
    }

    func testCommandTimeoutEscalationRequiresSameKnownIncarnation() {
        XCTAssertTrue(ProcessEscalationPolicy.permits(
            expectedToken: "child-a",
            currentToken: "child-a"
        ))
        XCTAssertFalse(ProcessEscalationPolicy.permits(
            expectedToken: "child-a",
            currentToken: "replacement-b"
        ))
        XCTAssertFalse(ProcessEscalationPolicy.permits(
            expectedToken: nil,
            currentToken: "child-a"
        ))
        XCTAssertFalse(ProcessEscalationPolicy.permits(
            expectedToken: "child-a",
            currentToken: nil
        ))
    }

    func testListeningIdentityRequiresSameSocketRowInConfirmationSnapshot() {
        let enriched = PortProcess(
            port: 3_000,
            protocolName: "tcp",
            pid: 42,
            user: "tester",
            command: "old-service",
            startTime: expected.startTime,
            processIdentityToken: "replacement-token",
            processPath: "/tmp/replacement"
        )
        let replacementElsewhere = PortProcess(
            port: 4_000,
            protocolName: "tcp",
            pid: 42,
            user: "tester",
            command: "replacement"
        )

        let disappeared = ProcessObservationBinding.listening(
            enriched: [enriched],
            confirmed: []
        )
        let changed = ProcessObservationBinding.listening(
            enriched: [enriched],
            confirmed: [replacementElsewhere]
        )
        let stable = ProcessObservationBinding.listening(
            enriched: [enriched],
            confirmed: [PortProcess(
                port: 3_000,
                protocolName: "tcp",
                pid: 42,
                user: "tester",
                command: "old-service"
            )]
        )
        let duplicateObserved = ProcessObservationBinding.listening(
            enriched: [enriched, enriched],
            confirmed: [PortProcess(
                port: 3_000,
                protocolName: "tcp",
                pid: 42,
                user: "tester",
                command: "old-service"
            )]
        )

        XCTAssertEqual(disappeared.count, 1, "Unconfirmed rows remain displayable")
        XCTAssertNil(disappeared[0].processIdentityToken)
        XCTAssertNil(changed[0].processIdentityToken)
        XCTAssertNil(ProcessIdentity(process: changed[0]))
        XCTAssertEqual(stable[0].processIdentityToken, "replacement-token")
        XCTAssertEqual(duplicateObserved.compactMap(\.processIdentityToken).count, 1)

        XCTAssertNil(ProcessObservationBinding.stableListeningIdentities(
            enriched: [],
            confirmed: [replacementElsewhere]
        ), "A holder appearing during capture must not become an empty Guard baseline")
        XCTAssertNil(ProcessObservationBinding.stableListeningIdentities(
            enriched: [PortProcess(
                port: enriched.port,
                protocolName: enriched.protocolName,
                pid: enriched.pid,
                user: enriched.user,
                command: enriched.command
            )],
            confirmed: [PortProcess(
                port: enriched.port,
                protocolName: enriched.protocolName,
                pid: enriched.pid,
                user: enriched.user,
                command: enriched.command
            )]
        ), "A stable row without a kernel identity must not arm Guard")
        XCTAssertEqual(ProcessObservationBinding.stableListeningIdentities(
            enriched: [enriched],
            confirmed: [PortProcess(
                port: enriched.port,
                protocolName: enriched.protocolName,
                pid: enriched.pid,
                user: enriched.user,
                command: enriched.command
            )]
        )?.map(\.incarnationToken), ["replacement-token"])
        XCTAssertEqual(ProcessObservationBinding.stableListeningIdentities(
            enriched: [],
            confirmed: []
        )?.count, 0, "Two complete empty snapshots prove the port was free")
    }

    func testConnectionIdentityRequiresSameEndpointRowInConfirmationSnapshot() {
        let enriched = EstablishedConnection(
            localAddress: "127.0.0.1:5_000",
            remoteAddress: "192.0.2.10:443",
            state: "ESTABLISHED",
            pid: 42,
            processName: "old-client",
            user: "tester",
            executablePath: "/tmp/replacement",
            processStartTime: expected.startTime,
            processIdentityToken: "replacement-token"
        )
        let changedEndpoint = EstablishedConnection(
            localAddress: "127.0.0.1:5_001",
            remoteAddress: "192.0.2.20:443",
            state: "ESTABLISHED",
            pid: 42,
            processName: "replacement",
            user: "tester"
        )

        let changed = ProcessObservationBinding.connections(
            enriched: [enriched],
            confirmed: [changedEndpoint]
        )
        let stable = ProcessObservationBinding.connections(
            enriched: [enriched],
            confirmed: [EstablishedConnection(
                localAddress: enriched.localAddress,
                remoteAddress: enriched.remoteAddress,
                state: enriched.state,
                pid: enriched.pid,
                processName: enriched.processName,
                user: enriched.user
            )]
        )

        XCTAssertNil(changed[0].processIdentityToken)
        XCTAssertNil(ProcessIdentity(connection: changed[0]))
        XCTAssertEqual(stable[0].processIdentityToken, "replacement-token")
    }

    func testNamedProcessIdentityRequiresSameNamedRowInConfirmationSnapshot() {
        let enriched = PortProcess(
            port: 0,
            protocolName: "process",
            pid: 42,
            user: "tester",
            command: "old-worker",
            startTime: expected.startTime,
            processIdentityToken: "replacement-token"
        )
        let replacement = PortProcess(
            port: 0,
            protocolName: "process",
            pid: 42,
            user: "tester",
            command: "replacement"
        )

        let result = ProcessObservationBinding.namedProcesses(
            enriched: [enriched],
            confirmed: [replacement]
        )

        XCTAssertNil(result[0].processIdentityToken)
        XCTAssertNil(ProcessIdentity(process: result[0]))
    }

    func testCurrentTestProcessHasStableReadableIdentity() throws {
        let manager = PortManager()
        let pid = Int(ProcessInfo.processInfo.processIdentifier)

        let first = try XCTUnwrap(manager.processIdentity(pid: pid))
        let second = try XCTUnwrap(manager.processIdentity(pid: pid))

        XCTAssertFalse(first.incarnationToken.isEmpty)
        XCTAssertEqual(first.incarnationToken, second.incarnationToken)
        XCTAssertTrue(first.matches(second))
    }
}
