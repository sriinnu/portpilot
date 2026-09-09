import XCTest
@testable import PortManagerLib

/// nextCronRun: dow 0/7, the Vixie dom/dow OR rule, and minute-boundary math.
/// All anchors are fixed 2026 dates (Sep 8 2026 is a Tuesday).
final class CronNextRunTests: XCTestCase {
    var manager: PortManager!
    var calendar: Calendar!

    override func setUp() {
        super.setUp()
        manager = PortManager()
        calendar = Calendar.current
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testNextMonday() {
        // Fri Sep 4 12:00 → Mon Sep 7 09:00
        let next = manager.nextCronRun(after: date(2026, 9, 4, 12, 0), schedule: "0 9 * * 1")
        XCTAssertEqual(next, date(2026, 9, 7, 9, 0))
        XCTAssertEqual(calendar.component(.weekday, from: next!), 2)  // Sunday=1 … Saturday=7
    }

    func testDowSevenMeansSunday() {
        // Sat Sep 5 → Sun Sep 6 09:00, from both "0" and "7" spellings.
        let anchor = date(2026, 9, 5, 12, 0)
        XCTAssertEqual(manager.nextCronRun(after: anchor, schedule: "0 9 * * 0"), date(2026, 9, 6, 9, 0))
        XCTAssertEqual(manager.nextCronRun(after: anchor, schedule: "0 9 * * 7"), date(2026, 9, 6, 9, 0))
    }

    func testDomAndDowAreORNotAND() {
        // "0 0 13 * 5" = the 13th OR any Friday (Vixie rule).
        // From Thu Sep 10: Friday Sep 11 fires before Sunday Sep 13.
        let fromThursday = manager.nextCronRun(after: date(2026, 9, 10, 20, 0), schedule: "0 0 13 * 5")
        XCTAssertEqual(fromThursday, date(2026, 9, 11, 0, 0))

        // From Tue Sep 8: the 13th (Sun) beats the next Monday-style match —
        // with dow=1 (Mon) the candidates are the 13th (dom) vs Mon Sep 14.
        let fromTuesday = manager.nextCronRun(after: date(2026, 9, 8, 10, 0), schedule: "0 0 13 * 1")
        XCTAssertEqual(fromTuesday, date(2026, 9, 13, 0, 0))
    }

    func testDowOnlyWhenDomIsStar() {
        // Tue Sep 8 → Mon Sep 14 08:30
        let next = manager.nextCronRun(after: date(2026, 9, 8, 12, 0), schedule: "30 8 * * 1")
        XCTAssertEqual(next, date(2026, 9, 14, 8, 30))
    }

    func testStepMinutesRoundUp() {
        // 10:07:30 → 10:15:00 (seconds truncated, next multiple of 15)
        let next = manager.nextCronRun(after: date(2026, 9, 8, 10, 7).addingTimeInterval(30), schedule: "*/15 * * * *")
        XCTAssertEqual(next, date(2026, 9, 8, 10, 15))
    }

    func testExactFireTimeAdvancesToNextSlot() {
        // At 10:15:00 the 10:15 slot is gone (search starts +1 minute).
        let next = manager.nextCronRun(after: date(2026, 9, 8, 10, 15), schedule: "*/15 * * * *")
        XCTAssertEqual(next, date(2026, 9, 8, 10, 30))
    }

    func testSameDayLaterHour() {
        // 09:00 daily from 14:00 → tomorrow 09:00.
        let next = manager.nextCronRun(after: date(2026, 9, 8, 14, 0), schedule: "0 9 * * *")
        XCTAssertEqual(next, date(2026, 9, 9, 9, 0))
    }

    func testMalformedScheduleReturnsNil() {
        XCTAssertNil(manager.nextCronRun(after: Date(), schedule: "0 9 * *"))
        XCTAssertNil(manager.nextCronRun(after: Date(), schedule: "not a cron"))
        XCTAssertNil(manager.nextCronRun(after: Date(), schedule: ""))
    }

    func testImpossibleDateReturnsNil() {
        // Feb 31 never exists — the 366-day search must give up, not loop forever.
        XCTAssertNil(manager.nextCronRun(after: date(2026, 9, 8), schedule: "0 0 31 2 *"))
    }
}
