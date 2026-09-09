import XCTest
@testable import PortManagerLib

/// Grandfathering semantics: whoever held the port when the guard was armed
/// is spared; everyone who binds afterwards is a victim.
final class PortGuardPolicyTests: XCTestCase {
    func testEmptySnapshotEvictsEveryone() {
        XCTAssertEqual(PortGuardPolicy.victims(currentPids: [1, 2, 3], grandfathered: []), [1, 2, 3])
    }

    func testGrandfatheredPidsAreSpared() {
        XCTAssertEqual(PortGuardPolicy.victims(currentPids: [1, 2, 3], grandfathered: [2]), [1, 3])
    }

    func testAllGrandfatheredYieldsNoVictims() {
        XCTAssertEqual(PortGuardPolicy.victims(currentPids: [4, 5], grandfathered: [4, 5]), [])
    }

    func testEmptyPortHasNoVictims() {
        XCTAssertEqual(PortGuardPolicy.victims(currentPids: [], grandfathered: [7]), [])
    }

    func testStaleGrandfatherEntriesAreInert() {
        // A grandfathered pid that has since died simply matches nothing.
        XCTAssertEqual(PortGuardPolicy.victims(currentPids: [9], grandfathered: [1, 2, 3]), [9])
    }
}
