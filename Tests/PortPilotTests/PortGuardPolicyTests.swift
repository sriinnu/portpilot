import XCTest
@testable import PortManagerLib

/// Pure fingerprint and generation tests. No process discovery or signals.
final class PortGuardPolicyTests: XCTestCase {
    func testDisarmImmediatelyRevokesAttemptWithoutWaitingForQueuedCleanup() {
        let gate = PortGuardEnforcementGate()
        let generation = gate.activate(port: 3_000)
        let delayedAttempt = { gate.permits(port: 3_000, generation: generation) }
        XCTAssertTrue(delayedAttempt())

        gate.invalidate(port: 3_000)

        // This is the predicate an already-running termination attempt retains;
        // no enforcement-queue cleanup needs to have executed for revocation.
        XCTAssertFalse(delayedAttempt())
    }

    func testRearmingDoesNotReviveThePreviousTerminationAttempt() {
        let gate = PortGuardEnforcementGate()
        let oldGeneration = gate.activate(port: 3_000)
        let oldAttempt = { gate.permits(port: 3_000, generation: oldGeneration) }
        var fakeSignals: [String] = []
        if oldAttempt() { fakeSignals.append("TERM") }

        gate.invalidate(port: 3_000)
        let newGeneration = gate.activate(port: 3_000)
        if oldAttempt() { fakeSignals.append("KILL") }

        XCTAssertNotEqual(oldGeneration, newGeneration)
        XCTAssertFalse(oldAttempt())
        XCTAssertTrue(gate.permits(port: 3_000, generation: newGeneration))
        XCTAssertEqual(fakeSignals, ["TERM"])
    }

    func testEnforcementGateKeepsPortsIndependent() {
        let gate = PortGuardEnforcementGate()
        let first = gate.activate(port: 3_000)
        let second = gate.activate(port: 4_000)

        gate.invalidate(port: 3_000)

        XCTAssertFalse(gate.permits(port: 3_000, generation: first))
        XCTAssertTrue(gate.permits(port: 4_000, generation: second))
        XCTAssertFalse(gate.permits(port: 5_000, generation: second))
    }

    private func identity(
        pid: Int,
        token: String? = nil,
        path: String? = "/tmp/service",
        user: String = "tester"
    ) -> ProcessIdentity {
        ProcessIdentity(
            pid: pid,
            startTime: Date(timeIntervalSince1970: 1_000),
            incarnationToken: token ?? "token-\(pid)",
            executablePath: path,
            user: user
        )
    }

    func testEmptySnapshotEvictsEveryone() {
        let current = [identity(pid: 2), identity(pid: 3)]
        XCTAssertEqual(PortGuardPolicy.victims(current: current, grandfathered: []), current)
    }

    func testGrandfatheredIncarnationsAreSpared() {
        let spared = identity(pid: 2)
        let victim = identity(pid: 3)
        XCTAssertEqual(
            PortGuardPolicy.victims(current: [spared, victim], grandfathered: [spared]),
            [victim]
        )
    }

    func testReusedPIDDoesNotInheritGrandfathering() {
        let original = identity(pid: 9, token: "old")
        let replacement = identity(pid: 9, token: "new")
        XCTAssertEqual(
            PortGuardPolicy.victims(current: [replacement], grandfathered: [original]),
            [replacement]
        )
    }

    func testSameIncarnationSurvivesTransientEnrichmentDifferences() {
        let original = identity(pid: 9, token: "same", path: "/tmp/service", user: "tester")
        let temporarilyUnenriched = identity(pid: 9, token: "same", path: nil, user: "unknown")
        XCTAssertTrue(
            PortGuardPolicy.victims(
                current: [temporarilyUnenriched],
                grandfathered: [original]
            ).isEmpty
        )
    }

    func testEmptyPortHasNoVictims() {
        XCTAssertTrue(
            PortGuardPolicy.victims(current: [], grandfathered: [identity(pid: 7)]).isEmpty
        )
    }

    func testPortLifecycleGenerationsAreIndependent() {
        var lifecycle = PortGuardLifecycle()
        let firstA = lifecycle.begin(port: 3_000)
        let firstB = lifecycle.begin(port: 4_000)

        lifecycle.invalidate(port: 3_000)

        XCTAssertFalse(lifecycle.isCurrent(port: 3_000, generation: firstA))
        XCTAssertTrue(lifecycle.isCurrent(port: 4_000, generation: firstB))
    }

    func testFailedSnapshotDoesNotArmAndSuccessfulRetryGrandfathersHolder() {
        var state = PortGuardBaselineState()
        let holder = identity(pid: 22)

        let failedGeneration = state.beginSnapshot(port: 3_000)
        XCTAssertTrue(state.completeSnapshot(
            port: 3_000,
            generation: failedGeneration,
            identities: nil
        ))
        XCTAssertNil(state.baseline(for: 3_000))

        let retryGeneration = state.beginSnapshot(port: 3_000)
        XCTAssertTrue(state.completeSnapshot(
            port: 3_000,
            generation: retryGeneration,
            identities: [holder]
        ))
        let baseline = try! XCTUnwrap(state.baseline(for: 3_000))
        XCTAssertTrue(PortGuardPolicy.victims(current: [holder], grandfathered: baseline).isEmpty)
    }

    func testDisablingOnePortDoesNotInvalidateAnotherPendingSnapshot() {
        var state = PortGuardBaselineState()
        let pendingA = state.beginSnapshot(port: 3_000)
        _ = state.beginSnapshot(port: 4_000)

        state.disable(port: 4_000)

        XCTAssertTrue(state.completeSnapshot(
            port: 3_000,
            generation: pendingA,
            identities: []
        ))
        XCTAssertEqual(state.baseline(for: 3_000), Set<ProcessIdentity>())
        XCTAssertNil(state.baseline(for: 4_000))
    }
}
