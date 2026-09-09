import XCTest
@testable import PortManagerLib

final class CronFieldTests: XCTestCase {
    var manager: PortManager!

    override func setUp() {
        super.setUp()
        manager = PortManager()
    }

    // MARK: - parseCronFieldValues

    func testStarExpandsToFullRange() {
        XCTAssertEqual(manager.parseCronFieldValues("*", min: 0, max: 59), Array(0...59))
        XCTAssertEqual(manager.parseCronFieldValues("*", min: 1, max: 12), Array(1...12))
    }

    func testStep() {
        XCTAssertEqual(manager.parseCronFieldValues("*/15", min: 0, max: 59), [0, 15, 30, 45])
        XCTAssertEqual(manager.parseCronFieldValues("*/6", min: 0, max: 23), [0, 6, 12, 18])
    }

    func testRange() {
        XCTAssertEqual(manager.parseCronFieldValues("1-5", min: 0, max: 59), [1, 2, 3, 4, 5])
    }

    func testRangeClampsToBounds() {
        XCTAssertEqual(manager.parseCronFieldValues("0-70", min: 0, max: 59), Array(0...59))
    }

    func testList() {
        XCTAssertEqual(manager.parseCronFieldValues("1,3,5", min: 0, max: 59), [1, 3, 5])
        // Lists of ranges and steps compose.
        XCTAssertEqual(manager.parseCronFieldValues("0,10,*/30", min: 0, max: 59), [0, 10, 30])
    }

    func testSingleValue() {
        XCTAssertEqual(manager.parseCronFieldValues("7", min: 0, max: 7), [7])
        XCTAssertEqual(manager.parseCronFieldValues("0", min: 0, max: 7), [0])
    }

    func testOutOfRangeAndGarbage() {
        XCTAssertEqual(manager.parseCronFieldValues("60", min: 0, max: 59), [])
        XCTAssertEqual(manager.parseCronFieldValues("mon", min: 0, max: 7), [])
        XCTAssertEqual(manager.parseCronFieldValues("", min: 0, max: 59), [])
    }

    // MARK: - humanReadableSchedule

    func testHumanReadableForms() {
        XCTAssertEqual(manager.humanReadableSchedule("* * * * *"), "Every minute")
        XCTAssertEqual(manager.humanReadableSchedule("*/15 * * * *"), "Every 15 min")
        XCTAssertEqual(manager.humanReadableSchedule("0 */6 * * *"), "Every 6h")
        XCTAssertEqual(manager.humanReadableSchedule("30 8 * * *"), "Daily @ 08:30")
        XCTAssertEqual(manager.humanReadableSchedule("0 9 * * 1"), "Weekly on Mon @ 09:00")
        XCTAssertEqual(manager.humanReadableSchedule("0 0 1 * *"), "Monthly on day 1 @ 00:00")
    }

    func testHumanReadableFallsBackToRaw() {
        XCTAssertEqual(manager.humanReadableSchedule("5 4 3 2 1"), "5 4 3 2 1")
        XCTAssertEqual(manager.humanReadableSchedule("0 9 * *"), "0 9 * *")  // <5 fields
    }
}
