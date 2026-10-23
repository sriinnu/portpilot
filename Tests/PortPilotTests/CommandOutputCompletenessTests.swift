import XCTest
@testable import PortManagerLib

final class CommandOutputCompletenessTests: XCTestCase {
    func testSuccessfulChildWithInheritedPipeCannotReturnCompleteOutput() throws {
        let started = Date()
        // Only disposable local processes. The background child retains the
        // pipe past the runner's one-second drain deadline, then exits itself.
        // Wait out its lifetime even when an assertion fails.
        defer {
            Thread.sleep(forTimeInterval: max(0, 2.2 - Date().timeIntervalSince(started)))
        }
        let result = PortManager().runProcess(
            "/bin/sh",
            arguments: ["-c", "(/bin/sleep 2; printf late) & printf early"]
        )

        XCTAssertEqual(result.exitStatus, 0)
        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.output, "early")
        XCTAssertTrue(result.outputTruncated, "Missing EOF must not authorize parsing partial output as complete")
        XCTAssertThrowsError(try PortManager.checkedCrontabRead(result))
    }
}
