import XCTest
@testable import PortManagerLib

final class ProcessClassifierTests: XCTestCase {
    let classifier = ProcessClassifier()

    func testKnownSystemDaemons() {
        XCTAssertEqual(classifier.classifyByPath("/usr/sbin/mDNSResponder"), .system)
        XCTAssertEqual(classifier.classifyByPath("/System/Library/CoreServices/Dock"), .system)
        XCTAssertEqual(classifier.classifyByPath("/usr/libexec/logd"), .system)
    }

    func testDevCommandBeatsUsrBinSystemPrefix() {
        // node in /usr/bin is a dev tool, not a system daemon — the dev
        // command check must run before the /usr/bin prefix check (matters
        // on Linux distros and macOS system Pythons).
        XCTAssertEqual(classifier.classifyByPath("/usr/bin/node"), .developerTool)
        XCTAssertEqual(classifier.classifyByPath("/usr/bin/python3"), .developerTool)
    }

    func testHomebrewPrefixIsDev() {
        XCTAssertEqual(classifier.classifyByPath("/opt/homebrew/bin/some-daemon"), .developerTool)
        XCTAssertEqual(classifier.classifyByPath("/usr/local/bin/redis-server"), .developerTool)
    }

    func testApplicationsAreUserApps() {
        XCTAssertEqual(classifier.classifyByPath("/Applications/Safari.app/Contents/MacOS/Safari"), .userApp)
        XCTAssertEqual(classifier.classifyByPath(NSHomeDirectory() + "/tools/server"), .userApp)
    }

    func testUnknownPathIsOther() {
        XCTAssertEqual(classifier.classifyByPath("/private/tmp/foo"), .other)
        XCTAssertEqual(classifier.classifyByPath("/opt/custom-thing/run"), .other)
    }
}
