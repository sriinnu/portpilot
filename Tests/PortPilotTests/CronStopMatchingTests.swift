import XCTest
@testable import PortManagerLib

/// Pins the cron-Stop matching contract: same executable AND (when the cron
/// command has arguments) the same leading argument tokens. This is the guard
/// against the old basename shotgun — `python3 /x/backup.py` used to kill
/// every python3 on the machine.
final class CronStopMatchingTests: XCTestCase {

    func testInterpreterCommandSpareUnrelatedInterpreterProcesses() {
        // The exact scenario that shipped: cron runs a backup script, the
        // user has an unrelated dev server under the same interpreter.
        XCTAssertFalse(PortManager.cronCommand(
            "python3 /Users/x/scripts/backup.py",
            matchesProcessCommand: "python3 -m http.server"
        ))
    }

    func testInterpreterCommandMatchesItsOwnScript() {
        XCTAssertTrue(PortManager.cronCommand(
            "python3 /Users/x/scripts/backup.py",
            matchesProcessCommand: "python3 /Users/x/scripts/backup.py"
        ))
    }

    func testScriptWithExtraRuntimeArgsStillMatches() {
        XCTAssertTrue(PortManager.cronCommand(
            "python3 /Users/x/scripts/backup.py",
            matchesProcessCommand: "python3 /Users/x/scripts/backup.py --verbose"
        ))
    }

    func testSameInterpreterDifferentScriptDoesNotMatch() {
        XCTAssertFalse(PortManager.cronCommand(
            "python3 /a/backup.py",
            matchesProcessCommand: "python3 /b/backup.py"
        ))
    }

    func testAbsoluteExecutableRequiresExactArgv0() {
        // /usr/bin/python3 and /opt/homebrew/bin/python3 are different programs.
        XCTAssertFalse(PortManager.cronCommand(
            "/usr/bin/python3 /x/backup.py",
            matchesProcessCommand: "/opt/homebrew/bin/python3 /x/backup.py"
        ))
        XCTAssertTrue(PortManager.cronCommand(
            "/usr/bin/python3 /x/backup.py",
            matchesProcessCommand: "/usr/bin/python3 /x/backup.py"
        ))
    }

    func testBareNameMatchesFullPathInvocation() {
        XCTAssertTrue(PortManager.cronCommand(
            "backup",
            matchesProcessCommand: "/usr/local/bin/backup"
        ))
        XCTAssertTrue(PortManager.cronCommand(
            "backup",
            matchesProcessCommand: "backup --nightly"
        ))
    }

    func testVimEditingCronOutputFileIsSpared() {
        // The original regression this matcher's ancestor fixed.
        XCTAssertFalse(PortManager.cronCommand(
            "/usr/local/bin/backup",
            matchesProcessCommand: "vim backup.conf"
        ))
    }

    func testFewerProcessArgsThanTargetArgsDoesNotMatch() {
        XCTAssertFalse(PortManager.cronCommand(
            "rsync -a --delete /src/ /dst/",
            matchesProcessCommand: "rsync -a"
        ))
    }

    func testEmptyOrMalformedInputNeverMatches() {
        XCTAssertFalse(PortManager.cronCommand("", matchesProcessCommand: "python3 /x/b.py"))
        XCTAssertFalse(PortManager.cronCommand("python3 /x/b.py", matchesProcessCommand: ""))
        XCTAssertFalse(PortManager.cronCommand("", matchesProcessCommand: ""))
        XCTAssertFalse(PortManager.cronCommand("   ", matchesProcessCommand: "python3"))
    }
}
