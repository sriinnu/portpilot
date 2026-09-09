import XCTest
@testable import PortManagerLib

/// parsePSLine carries the single-vs-double-digit-day fix: BSD `lstart` is
/// "Thu Sep  3 …" (space-padded day), which used to misalign token-splitting.
final class PSLineParserTests: XCTestCase {
    private func lstart(_ s: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter.date(from: s)!
    }

    func testWithUserSingleDigitDay() {
        // Two spaces before "3" — the classic alignment trap.
        let line = "12345 1 root Thu Sep  3 09:15:42 2026 /usr/sbin/cupsd -l"
        let parsed = PortManager.parsePSLine(line, hasUser: true)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.pid, 12345)
        XCTAssertEqual(parsed?.ppid, 1)
        XCTAssertEqual(parsed?.user, "root")
        XCTAssertEqual(parsed?.args, "/usr/sbin/cupsd -l")
        XCTAssertEqual(parsed?.startTime, lstart("Thu Sep 3 09:15:42 2026"))
    }

    func testWithUserDoubleDigitDay() {
        let line = "678 1 _nodebind Sat Sep 13 10:00:00 2025 node server.js"
        let parsed = PortManager.parsePSLine(line, hasUser: true)
        XCTAssertEqual(parsed?.pid, 678)
        XCTAssertEqual(parsed?.ppid, 1)
        XCTAssertEqual(parsed?.user, "_nodebind")
        XCTAssertEqual(parsed?.args, "node server.js")
        XCTAssertEqual(parsed?.startTime, lstart("Sat Sep 13 10:00:00 2025"))
    }

    func testNoUserVariant() {
        let line = "999 80 Thu Sep  3 09:15:42 2026 /usr/sbin/cupsd -l"
        let parsed = PortManager.parsePSLine(line, hasUser: false)
        XCTAssertEqual(parsed?.pid, 999)
        XCTAssertEqual(parsed?.ppid, 80)
        XCTAssertNil(parsed?.user)
        XCTAssertEqual(parsed?.args, "/usr/sbin/cupsd -l")
        XCTAssertEqual(parsed?.startTime, lstart("Thu Sep 3 09:15:42 2026"))
    }

    func testNoArgsStillParses() {
        let line = "42 1 Mon Jan  5 00:00:01 2026"
        let parsed = PortManager.parsePSLine(line, hasUser: false)
        XCTAssertEqual(parsed?.pid, 42)
        XCTAssertEqual(parsed?.ppid, 1)
        XCTAssertNil(parsed?.args)
    }

    func testGarbageReturnsNil() {
        for line in ["", "   ", "not a ps line", "pid ppid user lstart args"] {
            XCTAssertNil(PortManager.parsePSLine(line, hasUser: true), "should reject: \(line)")
            XCTAssertNil(PortManager.parsePSLine(line, hasUser: false), "should reject: \(line)")
        }
    }
}
