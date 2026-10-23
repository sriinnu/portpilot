import XCTest
@testable import PortManagerLib

final class CommandOutputCompletenessTests: XCTestCase {
    func testInheritedPipeOutputRequiresConfirmedEOFBeforeParsing() throws {
        let started = Date()
        // Only disposable local processes. The background child retains the
        // pipe after the direct child exits, then exits itself. Foundation may
        // report direct-child termination before EOF (Darwin) or after its
        // inherited output drains (Linux). Neither timing is an API guarantee.
        // Wait out the descendant's lifetime even when an assertion fails.
        defer {
            Thread.sleep(forTimeInterval: max(0, 2.2 - Date().timeIntervalSince(started)))
        }
        let result = PortManager().runProcess(
            "/bin/sh",
            arguments: ["-c", "(/bin/sleep 2; printf late) & printf early"]
        )

        XCTAssertEqual(result.exitStatus, 0)
        XCTAssertFalse(result.timedOut)
        if result.outputTruncated {
            XCTAssertEqual(result.output, "early")
            XCTAssertThrowsError(try PortManager.checkedCrontabRead(result),
                                 "Missing EOF must not authorize parsing partial output as complete")
        } else {
            XCTAssertEqual(result.output, "earlylate",
                           "Complete output must include the descendant's final write")
            XCTAssertEqual(try PortManager.checkedCrontabRead(result), "earlylate")
        }
    }
}
