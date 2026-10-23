import XCTest
@testable import PortManagerLib

final class InterfaceDirectionTests: XCTestCase {
    func testSevenDirectionsAreStableAndRestoreExactly() {
        XCTAssertEqual(InterfaceDirection.allCases.map(\.rawValue), ["Instrument", "Relay", "Fieldwork", "Focus", "Shell", "Play", "Orbit"])
        XCTAssertEqual(InterfaceDirection.allCases.map(\.number), ["01", "02", "03", "04", "05", "06", "07"])
        for direction in InterfaceDirection.allCases { XCTAssertEqual(InterfaceDirection.restoring(direction.rawValue), direction) }
    }
    func testRetiredPreferencesMigrateWithoutRemainingSelectable() {
        let retired = ["Classic": InterfaceDirection.instrument, "Graphite": .instrument, "Sunset": .fieldwork, "Oceanic": .focus, "Noir": .relay, "Paperwhite": .instrument, "Solarized": .shell, "Sentinel": .orbit, "Folio": .fieldwork]
        for (name, expected) in retired { XCTAssertEqual(InterfaceDirection.restoring(name), expected); XCTAssertNil(InterfaceDirection(rawValue: name)) }
        XCTAssertEqual(InterfaceDirection.restoring(nil), .instrument)
        XCTAssertEqual(InterfaceDirection.restoring("unknown future value"), .instrument)
    }
    func testShellNeverParsesEffectsOrCommandComposition() {
        for command in ["rm -rf /", "kill 3000", "stop 3000", "sudo ls", "ports; touch /tmp/x", "refresh && ls", "inspect $(id)", "inspect 3000 | sh", "inspect 0", "inspect 65536", "inspect -1", "inspect 80\nrefresh"] {
            XCTAssertEqual(WorkspaceCommand.parse(command), .invalid, command)
        }
        XCTAssertEqual(WorkspaceCommand.parse(" inspect 3000 "), .inspect(3000))
        XCTAssertEqual(WorkspaceCommand.parse("inspect 65535"), .inspect(65535))
        XCTAssertEqual(WorkspaceCommand.parse("find node --hello"), .find("node --hello"))
        XCTAssertEqual(WorkspaceCommand.parse("refresh"), .refresh)
        XCTAssertEqual(WorkspaceCommand.parse("observations"), .observations)
    }
}
