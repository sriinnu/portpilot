import XCTest
@testable import PortManagerLib

final class CrontabParserTests: XCTestCase {
    var manager: PortManager!

    override func setUp() {
        super.setUp()
        manager = PortManager()
    }

    func testUserCrontabHasNoUserColumn() {
        let output = """
        # a comment

        0 9 * * * /usr/bin/backup
        15 * * * 1 echo hi
        """
        let entries = manager.parseCrontab(output: output, source: "user", user: "sriinnu", hasUserColumn: false)
        XCTAssertEqual(entries.count, 2)

        XCTAssertEqual(entries[0].command, "/usr/bin/backup")
        XCTAssertEqual(entries[0].schedule, "0 9 * * *")
        XCTAssertEqual(entries[0].user, "sriinnu")
        XCTAssertFalse(entries[0].isPaused)

        XCTAssertEqual(entries[1].command, "echo hi")
        XCTAssertEqual(entries[1].schedule, "15 * * * 1")
    }

    func testSystemCrontabUserColumn() {
        // In /etc/cron.d style, field 6 is the user — it must not end up in the command.
        let entries = manager.parseCrontab(output: "0 9 * * * root /usr/bin/backup --quiet", source: "/etc/cron.d/backup", user: nil)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].user, "root")
        XCTAssertEqual(entries[0].command, "/usr/bin/backup --quiet")
        XCTAssertEqual(entries[0].source, "/etc/cron.d/backup")
    }

    func testAtMacrosExpand() {
        let entries = manager.parseCrontab(output: "@daily /opt/cleanup.sh", source: "user", user: "sriinnu", hasUserColumn: false)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].schedule, "0 0 * * *")
        XCTAssertEqual(entries[0].scheduleHuman, "Daily @ 00:00")
        XCTAssertEqual(entries[0].command, "/opt/cleanup.sh")
        XCTAssertNotNil(entries[0].nextRun)
    }

    func testAtRebootHasNoNextRun() {
        let entries = manager.parseCrontab(output: "@reboot /usr/local/bin/warm-cache", source: "user", user: "sriinnu", hasUserColumn: false)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].schedule, "@reboot")
        XCTAssertEqual(entries[0].scheduleHuman, "At reboot")
        XCTAssertNil(entries[0].nextRun)
    }

    func testPausedMarkerIsDetected() {
        let entries = manager.parseCrontab(output: "#PORTPILOT_PAUSED# */5 * * * * echo x", source: "user", user: nil, hasUserColumn: false)
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].isPaused)
        XCTAssertEqual(entries[0].schedule, "*/5 * * * *")
        XCTAssertEqual(entries[0].command, "echo x")
        // A paused job doesn't fire — no next-run time.
        XCTAssertNil(entries[0].nextRun)
    }

    func testShortAndGarbageLinesSkipped() {
        let output = """
        hello world
        0 9 * * *
        0 9 * * * nocommandhere
        """
        // "0 9 * * * nocommandhere" (5 fields + 1 token, no user column) →
        // command is empty → skipped.
        let entries = manager.parseCrontab(output: output, source: "user", user: nil, hasUserColumn: false)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].command, "nocommandhere")
    }

    func testAtMacroSystemCrontabKeepsUserColumn() {
        // /etc/cron.d macro lines carry the user too: "@daily root cmd" —
        // the username must not ride along inside the command.
        let entries = manager.parseCrontab(output: "@daily root /usr/local/bin/backup --quiet", source: "/etc/crontab", user: nil)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].user, "root")
        XCTAssertEqual(entries[0].command, "/usr/local/bin/backup --quiet")
        XCTAssertEqual(entries[0].schedule, "0 0 * * *")
    }

    func testAtRebootSystemCrontabUserColumn() {
        let entries = manager.parseCrontab(output: "@reboot deploy /opt/warm.sh", source: "/etc/cron.d/warm", user: nil)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].user, "deploy")
        XCTAssertEqual(entries[0].command, "/opt/warm.sh")
        XCTAssertEqual(entries[0].schedule, "@reboot")
    }

    func testDuplicateLinesGetUniqueIDs() {
        let entries = manager.parseCrontab(output: "0 2 * * * /bin/true\n0 2 * * * /bin/true\n", source: "user", user: "sriinnu", hasUserColumn: false)
        XCTAssertEqual(entries.count, 2)
        // Identical crontab lines must not collide on id — ForEach ids have
        // to stay unique.
        XCTAssertEqual(Set(entries.map(\.id)).count, 2)
        XCTAssertFalse(entries[0].id.hasSuffix("#2"))
        XCTAssertTrue(entries[1].id.hasSuffix("#2"))
    }

    func testDayOfWeekNameAcceptsSevenAsSunday() {
        // Cron accepts 0 and 7 for Sunday.
        XCTAssertEqual(manager.dayOfWeekName("7"), "Sun")
        XCTAssertEqual(manager.dayOfWeekName("0"), "Sun")
        XCTAssertEqual(manager.dayOfWeekName("3"), "Wed")
        XCTAssertEqual(manager.dayOfWeekName("sat"), "sat")
    }
}
