import XCTest
@testable import PortManagerLib

/// BlocklistEntry: CIDR math (the /33 shift trap, octet bounds) and host
/// matching, exercised through the public-ish `matches` path.
final class BlocklistTests: XCTestCase {
    func testMacOSConnectionStateSeparateAndAttachedTokens() {
        let snapshot = """
        COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
        fixture 123 tester 4u IPv4 0x1 0t0 TCP 127.0.0.1:5000->127.0.0.1:6000 (ESTABLISHED)
        fixture 124 tester 4u IPv4 0x1 0t0 TCP 127.0.0.1:5001->127.0.0.1:6001 (SYN_SENT)
        fixture 125 tester 4u IPv4 0x1 0t0 TCP 127.0.0.1:5002->127.0.0.1:6002(CLOSE_WAIT)
        """
        let connections = PortManager().parseMacOSAllConnections(snapshot)
        XCTAssertEqual(connections.map(\.state), ["ESTABLISHED", "SYN_SENT", "CLOSE_WAIT"])
        XCTAssertEqual(connections.last?.remoteAddress, "127.0.0.1:6002")
    }

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

    func testLeadingDotDomainSuffixMatchesDocumentedForm() {
        XCTAssertTrue(entry(".evil.com").matches("evil.com:443", hostname: nil))
        XCTAssertTrue(entry(".evil.com").matches("1.2.3.4:80", hostname: "cdn.evil.com"))
        XCTAssertFalse(entry(".evil.com").matches("1.2.3.4:80", hostname: "notevil.com"))
    }

    func testDomainCanonicalizationHandlesCaseAndTerminalDot() {
        XCTAssertTrue(entry(".Evil.COM.").matches("evil.com.:443", hostname: nil))
        XCTAssertTrue(entry(".Evil.COM.").matches("1.2.3.4:80", hostname: "CDN.EVIL.COM."))
        XCTAssertFalse(entry(".").matches("anything.example:443", hostname: "anything.example"))
    }

    #if canImport(Network)
    func testProxyAccessPolicyDefaultsToLoopbackOnly() throws {
        let policy = ProxyAccessPolicy.loopback
        try policy.validate()
        XCTAssertTrue(policy.permits(address: "127.0.0.1"))
        XCTAssertTrue(policy.permits(address: "::1"))
        XCTAssertFalse(policy.permits(address: "192.168.1.20"))
    }

    func testProxyAccessPolicyScopesLANByCIDR() throws {
        let policy = ProxyAccessPolicy.allowedCIDRs(["192.168.1.0/24", "fd00::/8"])
        try policy.validate()
        XCTAssertTrue(policy.permits(address: "192.168.1.20"))
        XCTAssertTrue(policy.permits(address: "fd00::42"))
        XCTAssertFalse(policy.permits(address: "192.168.2.20"))
        XCTAssertThrowsError(try ProxyAccessPolicy.allowedCIDRs([]).validate())
        XCTAssertThrowsError(try ProxyAccessPolicy.allowedCIDRs(["not-a-network"]).validate())
    }

    func testProxyAccessPolicyRejectsAllAddressCIDRs() {
        XCTAssertThrowsError(try ProxyAccessPolicy.allowedCIDRs(["0.0.0.0/0"]).validate())
        XCTAssertThrowsError(try ProxyAccessPolicy.allowedCIDRs(["::/0"]).validate())
    }

    func testProxyAccessPolicyAcceptsSingleClientCIDRs() throws {
        try ProxyAccessPolicy.allowedCIDRs(["192.0.2.10/32", "2001:db8::10/128"]).validate()
    }

    func testProxyRejectsInvalidPortsBeforeListening() {
        let manager = TCPProxyManager()
        for port in [-1, 0, 65_536] {
            XCTAssertThrowsError(try manager.startProxy(listenPort: port, targetHost: "127.0.0.1", targetPort: 80))
            XCTAssertThrowsError(try manager.startProxy(listenPort: 8_080, targetHost: "127.0.0.1", targetPort: port))
        }
    }
    #endif

    func testDomainSuffixIsNotSubstring() {
        // "notevil.com" must not match pattern "evil.com".
        XCTAssertFalse(entry("evil.com").matches("1.2.3.4:80", hostname: "notevil.com"))
        XCTAssertFalse(entry("evil.com").matches("1.2.3.4:80", hostname: "good.com"))
    }
}
