import XCTest
@testable import PortManagerLib

final class PacketCaptureTests: XCTestCase {
    private func request(duration: TimeInterval = 1) throws -> PacketCaptureRequest {
        try PacketCaptureRequest(interface: "lo0", port: 43210, transport: "TCP", duration: duration)
    }
    func testFiltersAreNumericAndNeverEnablePayloadPrintingOrPromiscuousMode() throws {
        let args = try request().arguments
        XCTAssertEqual(args.last, "tcp port 43210")
        XCTAssertTrue(args.contains("-p"))
        XCTAssertTrue(args.contains("-n"))
        for forbidden in ["-A", "-X", "-w", "-vv"] { XCTAssertFalse(args.contains(forbidden)) }
        for bad in ["", "-i", "lo0;touch", "../en0", "any\n-w", String(repeating: "a", count: 33)] {
            XCTAssertThrowsError(try PacketCaptureRequest(interface: bad, port: 80, transport: "tcp"))
        }
        for port in [-1, 0, 65536] {
            XCTAssertThrowsError(try PacketCaptureRequest(interface: "lo0", port: port, transport: "udp"))
        }
        XCTAssertThrowsError(try PacketCaptureRequest(interface: "lo0", port: 80, transport: "unix"))
        for duration in [0, 31, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try request(duration: duration))
        }
        XCTAssertThrowsError(try PacketCaptureRequest(interface: "lo0", port: 80, transport: "udp", packetLimit: 201))
    }
    func testIPv4IPv6SummariesAndDiagnosticSeparation() {
        let tcp = PacketSummary.parse("1729700000.123456 IP 127.0.0.1.50123 > 127.0.0.1.43210: tcp 0")
        XCTAssertEqual(tcp?.source, "127.0.0.1.50123")
        XCTAssertEqual(tcp?.destination, "127.0.0.1.43210")
        let udp = PacketSummary.parse("1729700000.123457 IP6 ::1.50123 > ::1.43210: UDP, length 8")
        XCTAssertEqual(udp?.detail, "UDP, length 8")
        for line in ["tcpdump: permission denied", "0 packets captured", "listening on lo0", "secret payload", "123 IP evil > remote: decoded payload"] {
            XCTAssertNil(PacketSummary.parse(line))
        }
    }
    func testSyntheticCaptureParsesOnlyPacketLines() throws {
        let session = PacketCaptureSession(request: try request(), executable: "/usr/bin/printf",
            arguments: ["%s\n", "1729700000.123456 IP 127.0.0.1.50123 > 127.0.0.1.43210: tcp 0", "1 packet captured"])
        let result = session.run()
        XCTAssertFalse(result.failed)
        XCTAssertFalse(result.truncated)
        XCTAssertEqual(result.packets.count, 1)
        XCTAssertEqual(session.run().packets.count, 0, "One-use sessions cannot restart capture")
    }
    func testSyntheticPermissionFailureIsNotAnEmptySuccessfulCapture() throws {
        let session = PacketCaptureSession(request: try request(), executable: "/bin/sh",
            arguments: ["-c", "printf 'tcpdump: permission denied\\n' >&2; exit 1"])
        let result = session.run()
        XCTAssertTrue(result.failed)
        XCTAssertTrue(result.message.contains("cannot access"))
        XCTAssertTrue(result.packets.isEmpty)
    }
    func testDeadlineAndCancellationSettleOnlyDisposableChildren() throws {
        let deadline = PacketCaptureSession(request: try request(), executable: "/bin/sleep", arguments: ["20"])
        let start = Date()
        let result = deadline.run()
        XCTAssertFalse(result.failed, result.message)
        XCTAssertTrue(deadline.waitUntilFinished(timeout: 0))
        XCTAssertTrue(result.message.contains("Timed"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)

        let cancelled = PacketCaptureSession(request: try request(duration: 30), executable: "/bin/sleep", arguments: ["20"])
        let done = expectation(description: "Cancelled child settled")
        DispatchQueue.global().async {
            let result = cancelled.run()
            XCTAssertFalse(result.failed, result.message)
            XCTAssertTrue(result.message.contains("stopped") || result.message.contains("cancelled"))
            done.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.15)
        cancelled.cancel()
        wait(for: [done], timeout: 4)
    }
    func testLateNaturalExitEventuallyConfirmsCleanup() throws {
        // Refuse all signals through an unavailable identity. Only this disposable
        // child runs, and it exits naturally after the bounded cleanup wait.
        let session = PacketCaptureSession(request: try request(), executable: "/bin/sleep",
            arguments: ["6"], identityProvider: { _ in nil })
        let result = session.run()
        XCTAssertTrue(result.failed)
        XCTAssertFalse(session.waitUntilFinished(timeout: 0))
        XCTAssertTrue(session.waitUntilFinished(timeout: 4), "Late exit must unblock capture retry and normal Quit")
    }

    func testOutputLimitIsReported() throws {
        let session = PacketCaptureSession(request: try request(), executable: "/bin/sh",
            arguments: ["-c", "i=0; while [ $i -lt 5000 ]; do printf '%s\\n' '1729700000.123456 IP 127.0.0.1.50123 > 127.0.0.1.43210: tcp 0'; i=$((i+1)); done"])
        let result = session.run()
        XCTAssertTrue(result.truncated)
        XCTAssertLessThanOrEqual(result.packets.count, 200)
    }
    func testLaunchFailureAndPreStartCancellation() throws {
        let missing = PacketCaptureSession(request: try request(), executable: "/nonexistent/portpilot-synthetic", arguments: [])
        XCTAssertTrue(missing.run().failed)
        let cancelled = PacketCaptureSession(request: try request(), executable: "/bin/sleep", arguments: ["20"])
        cancelled.cancel()
        XCTAssertEqual(cancelled.run().message, "Capture cancelled.")
    }
}
