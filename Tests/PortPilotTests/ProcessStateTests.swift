import XCTest
@testable import PortManagerLib

/// ps STAT leading-letter semantics used to surface paused (SIGSTOPped)
/// processes. macOS prints `T` (optionally with modifiers like `T+`);
/// Linux can also print lowercase `t` for a tracing stop.
final class ProcessStateTests: XCTestCase {
    func testStoppedStates() {
        XCTAssertTrue(PortManager.isStoppedState("T"))
        XCTAssertTrue(PortManager.isStoppedState("T+"))
        XCTAssertTrue(PortManager.isStoppedState("Ts"))
        XCTAssertTrue(PortManager.isStoppedState("t"))
    }

    func testRunningStates() {
        XCTAssertFalse(PortManager.isStoppedState("S"))
        XCTAssertFalse(PortManager.isStoppedState("Ss"))
        XCTAssertFalse(PortManager.isStoppedState("R+"))
        XCTAssertFalse(PortManager.isStoppedState("U"))
        XCTAssertFalse(PortManager.isStoppedState("Z+"))
    }

    func testEmptyState() {
        XCTAssertFalse(PortManager.isStoppedState(""))
    }

    func testIsStoppedSurvivesCodableRoundTrip() throws {
        var process = PortProcess(port: 3000, protocolName: "TCP", pid: 42, user: "dev", command: "node")
        process.isStopped = true

        let data = try JSONEncoder().encode(process)
        let decoded = try JSONDecoder().decode(PortProcess.self, from: data)

        XCTAssertTrue(decoded.isStopped)
    }

    func testIsStoppedDefaultsFalse() {
        let process = PortProcess(port: 3000, protocolName: "TCP", pid: 42, user: "dev", command: "node")
        XCTAssertFalse(process.isStopped)

        // Equality stays identity-based — a freeze doesn't change who the
        // process is, so list diffs don't reshuffle on pause.
        var other = process
        other.isStopped = true
        XCTAssertEqual(process, other)
    }
}
