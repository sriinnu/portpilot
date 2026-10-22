#if canImport(Network)
import Foundation
import Network
import XCTest
@testable import PortManagerLib

/// Only owned ephemeral listeners and 127.0.0.1 clients; no external endpoint.
final class ProxyIntegrationTests: XCTestCase {
    private func eventually(_ predicate: () -> Bool, timeout: TimeInterval = 4,
                            file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(predicate(), file: file, line: line)
    }

    private func start(_ manager: TCPProxyManager, target: LoopbackEcho,
                       policy: ProxyAccessPolicy = .loopback,
                       limit: Int = 64, idle: TimeInterval = 300) throws -> ProxySession {
        // Reserve an OS-selected loopback port, then release it immediately.
        // A bind race is reported as failure, never redirected to another host.
        let reservation = try LoopbackEcho()
        eventually { reservation.port != nil }
        let port = try XCTUnwrap(reservation.port)
        reservation.stop()
        eventually { reservation.isStopped }
        var ready = false
        var error: String?
        manager.onLog = { if $0.hasPrefix("Proxy listening") { ready = true } }
        manager.onError = { _, message in error = message }
        let session = try manager.startProxy(listenPort: Int(port), targetHost: "127.0.0.1",
                                            targetPort: Int(try XCTUnwrap(target.port)),
                                            accessPolicy: policy, connectionLimit: limit, idleTimeout: idle)
        eventually { ready || error != nil }
        guard ready, error == nil, manager.getSession(id: session.id)?.isActive == true else {
            manager.stopProxy(id: session.id)
            throw NSError(domain: "ProxyIntegrationTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: error ?? "Owned proxy listener did not become ready"])
        }
        return session
    }

    private func client(_ port: Int) -> NWConnection {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(port))!, using: .tcp)
        connection.start(queue: .main)
        return connection
    }

    func testLoopbackForwardsBytesAndCanStopAndRestart() throws {
        let target = try LoopbackEcho()
        defer { target.stop() }
        eventually { target.port != nil }
        let manager = TCPProxyManager(loopbackOnlyForTesting: true)
        defer { manager.stopAll() }
        let session = try start(manager, target: target)
        let connection = client(session.listenPort)
        defer { connection.cancel() }
        let payload = Data("owned-local-fixture".utf8)
        var received: Data?
        connection.receive(minimumIncompleteLength: payload.count, maximumLength: 1024) { data, _, _, _ in received = data }
        connection.send(content: payload, completion: .contentProcessed { _ in })
        eventually { received != nil }
        XCTAssertEqual(received, payload)
        eventually { (manager.getSession(id: session.id)?.bytesForwarded ?? 0) >= UInt64(payload.count * 2) }
        manager.stopProxy(id: session.id)
        XCTAssertNil(manager.getSession(id: session.id))
        let restarted = try start(manager, target: target)
        XCTAssertNotEqual(session.id, restarted.id)
        XCTAssertEqual(manager.getActiveSessions().count, 1)
    }

    func testDeniedPeerDoesNotOpenTargetConnection() throws {
        let target = try LoopbackEcho()
        defer { target.stop() }
        eventually { target.port != nil }
        let manager = TCPProxyManager(loopbackOnlyForTesting: true)
        defer { manager.stopAll() }
        // Test-only bind restriction keeps custom-policy admission on loopback.
        let session = try start(manager, target: target, policy: .allowedCIDRs(["192.0.2.1/32"]))
        var rejected = false
        manager.onLog = { if $0.hasPrefix("Rejected proxy client") { rejected = true } }
        let connection = client(session.listenPort)
        defer { connection.cancel() }
        eventually { rejected }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(target.acceptedCount, 0)
        XCTAssertEqual(manager.getSession(id: session.id)?.activeConnections, 0)
    }

    func testConnectionLimitAndIdleCleanup() throws {
        let target = try LoopbackEcho()
        defer { target.stop() }
        eventually { target.port != nil }
        let manager = TCPProxyManager(loopbackOnlyForTesting: true)
        defer { manager.stopAll() }
        let session = try start(manager, target: target, limit: 1, idle: 1)
        let first = client(session.listenPort)
        defer { first.cancel() }
        eventually { target.acceptedCount == 1 }
        var rejected = false
        manager.onLog = { if $0.hasPrefix("Rejected proxy client") { rejected = true } }
        let second = client(session.listenPort)
        defer { second.cancel() }
        eventually { rejected }
        XCTAssertEqual(target.acceptedCount, 1)
        XCTAssertEqual(manager.getSession(id: session.id)?.activeConnections, 1)
        eventually { manager.getSession(id: session.id)?.activeConnections == 0 }
        let third = client(session.listenPort)
        defer { third.cancel() }
        eventually { target.acceptedCount == 2 }
    }
}

private final class LoopbackEcho {
    private let listener: NWListener
    private var accepted: [NWConnection] = []
    private var isReady = false
    private(set) var isStopped = false
    var port: UInt16? {
        guard isReady, let port = listener.port?.rawValue, port > 0 else { return nil }
        return port
    }
    var acceptedCount: Int { accepted.count }

    init() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters, on: .any)
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state { self?.isReady = true }
            if case .cancelled = state { self?.isStopped = true }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            self.accepted.append(connection)
            connection.start(queue: .main)
            self.echo(connection)
        }
        listener.start(queue: .main)
    }

    private func echo(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                connection.send(content: data, completion: .contentProcessed { _ in })
            }
            if !complete, error == nil { self.echo(connection) }
        }
    }

    func stop() {
        listener.cancel()
        accepted.forEach { $0.cancel() }
    }
}
#endif
