import XCTest
@testable import PortManagerLib

/// Synthetic plists only. All anchors are fixed 2026 dates (Sep 8 2026 is a Tuesday).
final class LaunchdDiscoveryTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: mo, day: d, hour: h, minute: mi))!
    }

    private func plist(_ dict: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    private func parse(_ dict: [String: Any], now: Date? = nil) throws -> LaunchdPlist.Parsed? {
        try LaunchdPlist.parse(plist(dict), now: now ?? date(9, 8, 12), calendar: calendar)
    }

    func testDailyCalendarJob() throws {
        let job = try XCTUnwrap(parse([
            "Label": "com.example.nightly",
            "ProgramArguments": ["/bin/sh", "run.sh", "--yes"],
            "StartCalendarInterval": ["Hour": 3, "Minute": 30],
            "StandardOutPath": "/tmp/nightly.log",
        ]))
        XCTAssertEqual(job.label, "com.example.nightly")
        XCTAssertEqual(job.command, "/bin/sh run.sh --yes")
        XCTAssertEqual(job.scheduleHuman, "Daily at 03:30")
        XCTAssertEqual(job.nextRun, date(9, 9, 3, 30))
        XCTAssertEqual(job.logPath, "/tmp/nightly.log")
    }

    func testIntervalJobHasNoInventedNextRun() throws {
        let job = try XCTUnwrap(parse(["Label": "a", "Program": "/bin/true", "StartInterval": 7_200]))
        XCTAssertEqual(job.scheduleHuman, "Every 2 hours")
        XCTAssertNil(job.nextRun)
        XCTAssertEqual(job.command, "/bin/true")
    }

    func testIntervalWording() {
        XCTAssertEqual(LaunchdPlist.describe(seconds: 86_400), "Every day")
        XCTAssertEqual(LaunchdPlist.describe(seconds: 21_600), "Every 6 hours")
        XCTAssertEqual(LaunchdPlist.describe(seconds: 604_800), "Every week")
        XCTAssertEqual(LaunchdPlist.describe(seconds: 90), "Every 90 seconds")
    }

    func testAgentWithoutScheduleIsNotAJob() throws {
        XCTAssertNil(try parse(["Label": "daemon", "Program": "/bin/true", "KeepAlive": true]))
        XCTAssertNil(try parse([:]), "an empty plist isn't a job, and isn't an error")
    }

    func testSundayIsZeroOrSeven() throws {
        let zero = ["Weekday": 0, "Hour": 9, "Minute": 0]
        let seven = ["Weekday": 7, "Hour": 9, "Minute": 0]
        XCTAssertEqual(LaunchdPlist.nextFire(of: zero, after: date(9, 8, 12), calendar: calendar), date(9, 13, 9, 0))
        XCTAssertEqual(LaunchdPlist.nextFire(of: seven, after: date(9, 8, 12), calendar: calendar), date(9, 13, 9, 0))
        XCTAssertEqual(LaunchdPlist.describe(zero), "Sundays at 09:00")
        XCTAssertEqual(LaunchdPlist.describe(seven), "Sundays at 09:00")
    }

    func testDayAndWeekdayFireOnEitherLikeCron() {
        // Day 20, or Wednesdays: Sep 9 comes first.
        let interval = ["Day": 20, "Weekday": 3, "Hour": 1, "Minute": 0]
        XCTAssertEqual(LaunchdPlist.nextFire(of: interval, after: date(9, 8, 12), calendar: calendar), date(9, 9, 1, 0))
    }

    func testSeveralCalendarTimesUseTheSoonest() throws {
        let job = try XCTUnwrap(parse([
            "Label": "a", "Program": "/bin/true",
            "StartCalendarInterval": [["Hour": 23, "Minute": 0], ["Hour": 13, "Minute": 0]],
        ]))
        XCTAssertEqual(job.scheduleHuman, "2 calendar times")
        XCTAssertEqual(job.nextRun, date(9, 8, 13, 0))
    }

    func testBadInputIsAnErrorNotAnEmptyResult() throws {
        XCTAssertThrowsError(try LaunchdPlist.parse(Data("nope".utf8), now: date(9, 8))) {
            XCTAssertEqual($0 as? LaunchdPlist.ParseError, .notAPlist)
        }
        XCTAssertThrowsError(try parse(["Program": "/bin/true", "StartInterval": 60])) {
            XCTAssertEqual($0 as? LaunchdPlist.ParseError, .noLabel)
        }
        XCTAssertThrowsError(try parse(["Label": "a", "StartInterval": 0])) {
            XCTAssertEqual($0 as? LaunchdPlist.ParseError, .badSchedule("StartInterval"))
        }
        XCTAssertThrowsError(try parse(["Label": "a", "StartCalendarInterval": ["Hour": 25]])) {
            XCTAssertEqual($0 as? LaunchdPlist.ParseError, .badSchedule("StartCalendarInterval"))
        }
    }

    func testRuntimeStateReadsOnlyTheJobsOwnLines() {
        let output = """
        gui/501/com.example = {
        \tactive count = 0
        \tstate = not running
        \truns = 4
        \tlast exit code = 78
        \tendpoints = {
        \t\tstate = active
        \t\truns = 99
        \t}
        }
        """
        XCTAssertEqual(LaunchdPlist.parseRuntimeState(output),
                       .init(isRunning: false, lastExitCode: 78, runCount: 4))
        XCTAssertNil(LaunchdPlist.parseRuntimeState("\tlast exit code = (never exited)").lastExitCode)
    }

    func testEnvironmentSecretsNeverReachOutput() throws {
        let planted = "planted-environment-value"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try plist([
            "Label": "test.portpilot.secret.\(UUID().uuidString)",
            "ProgramArguments": ["/bin/true"],
            "StartInterval": 60,
            "EnvironmentVariables": ["PLANTED_NAME": planted],
        ]).write(to: dir.appendingPathComponent("job.plist"))

        let snapshot = PortManager().getLaunchdSnapshot(directory: dir)
        XCTAssertEqual(snapshot.entries.count, 1)
        XCTAssertTrue(snapshot.isComplete, snapshot.errorDescription)
        XCTAssertEqual(snapshot.entries[0].loadState, .notLoaded)
        let json = try String(decoding: JSONEncoder().encode(snapshot.entries), as: UTF8.self)
        XCTAssertFalse(json.contains(planted))
        XCTAssertFalse(json.contains("PLANTED_NAME"))
    }

    func testSnapshotReportsABrokenFileAlongsideGoodOnes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("broken".utf8).write(to: dir.appendingPathComponent("bad.plist"))
        try plist(["Label": "test.portpilot.good.\(UUID().uuidString)", "Program": "/bin/true", "StartInterval": 60])
            .write(to: dir.appendingPathComponent("good.plist"))
        try plist(["Label": "test.portpilot.daemon", "Program": "/bin/true", "KeepAlive": true])
            .write(to: dir.appendingPathComponent("daemon.plist"))

        let snapshot = PortManager().getLaunchdSnapshot(directory: dir)
        XCTAssertEqual(snapshot.entries.count, 1)
        XCTAssertEqual(snapshot.unscheduledCount, 1)
        XCTAssertFalse(snapshot.isComplete)
        XCTAssertTrue(snapshot.errorDescription.contains("bad.plist"))
    }

    func testMissingFolderIsEmptyAndComplete() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let snapshot = PortManager().getLaunchdSnapshot(directory: dir)
        XCTAssertTrue(snapshot.isComplete)
        XCTAssertTrue(snapshot.entries.isEmpty)
    }
}
