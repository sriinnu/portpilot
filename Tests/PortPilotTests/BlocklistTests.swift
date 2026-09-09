import XCTest
@testable import PortManagerLib

/// BlocklistEntry: CIDR math (the /33 shift trap, octet bounds) and host
/// matching, exercised through the public-ish `matches` path.
final class BlocklistTests: XCTestCase {
    private func entry(_ line: String) -> PortManager.BlocklistEntry {
        PortManager.BlocklistEntry(line)
    }

    // MARK: - Exact IP

    func testPortIsStrippedBeforeCompare() {
        XCTAssertTrue(entry("10.0.0.5").matches("10.0.0.5:443", hostname: nil))
        XCTAssertFalse(entry("10.0.0.5").matches("10.0.0.6:443", hostname: nil))
    }

    // MARK: - CIDR

    func testCIDR24() {
        XCTAssertTrue(entry("192.168.1.0/24").matches("192.168.1.77:80", hostname: nil))
        XCTAssertFalse(entry("192.168.1.0/24").matches("192.168.2.77:80", hostname: nil))
    }

    func testCIDR8AndZero() {
        XCTAssertTrue(entry("10.0.0.0/8").matches("10.255.3.4:22", hostname: nil))
        XCTAssertFalse(entry("10.0.0.0/8").matches("11.0.0.1:22", hostname: nil))
        XCTAssertTrue(entry("0.0.0.0/0").matches("203.0.113.9:80", hostname: nil))
    }

    func testPrefixBeyond32DoesNotTrap() {
        // Used to trap on `1 << (32 - 33)`. Now: no match, no crash.
        XCTAssertFalse(entry("1.2.3.4/33").matches("1.2.3.4:80", hostname: nil))
        // IPv6 syntax against the IPv4-only parser: no match, no crash.
        XCTAssertFalse(entry("::1/64").matches("::1", hostname: nil))
    }

    func testInvalidOctetsRejected() {
        // 256 isn't a valid octet — used to fold into the address silently.
        XCTAssertFalse(entry("10.0.0.0/8").matches("999.999.999.999:80", hostname: nil))
        XCTAssertFalse(entry("10.0.0.0/8").matches("not-an-ip", hostname: nil))
    }

    func testIPv6BracketFormExtractsHost() {
        XCTAssertTrue(entry("2001:db8::1").matches("[2001:db8::1]:443", hostname: nil))
    }

    // MARK: - Hostname / domain suffix

    func testDomainSuffixMatches() {
        XCTAssertTrue(entry("evil.com").matches("1.2.3.4:80", hostname: "cdn.evil.com"))
        XCTAssertTrue(entry("evil.com").matches("evil.com:443", hostname: nil))
    }

    func testDomainSuffixIsNotSubstring() {
        // "notevil.com" must not match pattern "evil.com".
        XCTAssertFalse(entry("evil.com").matches("1.2.3.4:80", hostname: "notevil.com"))
        XCTAssertFalse(entry("evil.com").matches("1.2.3.4:80", hostname: "good.com"))
    }
}
