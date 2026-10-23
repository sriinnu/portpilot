import Foundation

#if canImport(Network)
import Network

/// Source-IP admission policy, not client authentication or encryption.
/// Custom CIDRs opt into an all-interface listener; broad /0 policies expose it widely.
public enum ProxyAccessPolicy: Hashable, Sendable {
    case loopback
    case allowedCIDRs([String])

    public func validate() throws {
        switch self {
        case .loopback:
            return
        case .allowedCIDRs(let values):
            guard !values.isEmpty, values.allSatisfy({ ProxyCIDR($0) != nil }) else {
                throw ProxyError.invalidAccessPolicy("Enter one or more valid IPv4 or IPv6 CIDRs.")
            }
        }
    }

    public func permits(address: String) -> Bool {
        let host = address.split(separator: "%", maxSplits: 1).first.map(String.init) ?? address
        switch self {
        case .loopback:
            return ProxyCIDR("127.0.0.0/8")?.contains(host) == true
                || ProxyCIDR("::1/128")?.contains(host) == true
        case .allowedCIDRs(let values):
            return values.compactMap(ProxyCIDR.init).contains { $0.contains(host) }
        }
    }

    public var displayName: String {
        switch self {
        case .loopback: return "This Mac only"
        case .allowedCIDRs(let values): return values.joined(separator: ", ")
        }
    }
}

private struct ProxyCIDR {
    let bytes: Data
    let prefixLength: Int

    init?(_ value: String) {
        let parts = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard let hostPart = parts.first, !hostPart.isEmpty else { return nil }
        let host = String(hostPart)

        if let address = IPv4Address(host) {
            let prefix = parts.count == 2 ? Int(parts[1]) : 32
            guard let prefix, (0...32).contains(prefix) else { return nil }
            self.bytes = address.rawValue
            self.prefixLength = prefix
        } else if let address = IPv6Address(host) {
            let prefix = parts.count == 2 ? Int(parts[1]) : 128
            guard let prefix, (0...128).contains(prefix) else { return nil }
            self.bytes = address.rawValue
            self.prefixLength = prefix
        } else {
            return nil
        }
    }

    func contains(_ host: String) -> Bool {
        let candidate: Data
        if bytes.count == 4, let address = IPv4Address(host) {
            candidate = address.rawValue
        } else if bytes.count == 16, let address = IPv6Address(host) {
            candidate = address.rawValue
        } else {
            return false
        }

        let fullBytes = prefixLength / 8
        let remainingBits = prefixLength % 8
        if fullBytes > 0 && candidate.prefix(fullBytes) != bytes.prefix(fullBytes) { return false }
        guard remainingBits > 0 else { return true }
        let mask = UInt8.max << (8 - remainingBits)
        return (candidate[fullBytes] & mask) == (bytes[fullBytes] & mask)
    }
}

public struct ProxySession: Identifiable, Hashable {
    public let id: UUID
    public let listenPort: Int
    public let targetHost: String
    public let targetPort: Int
    public let accessPolicy: ProxyAccessPolicy
    public let connectionLimit: Int
    public let idleTimeout: TimeInterval
    public let createdAt: Date
    public var isActive: Bool
    public var bytesForwarded: UInt64
    public var activeConnections: Int

    public init(
        id: UUID = UUID(), listenPort: Int, targetHost: String, targetPort: Int,
        accessPolicy: ProxyAccessPolicy = .loopback,
        connectionLimit: Int = 64, idleTimeout: TimeInterval = 300
    ) {
        self.id = id
        self.listenPort = listenPort
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.accessPolicy = accessPolicy
        self.connectionLimit = connectionLimit
        self.idleTimeout = idleTimeout
        self.createdAt = Date()
        self.isActive = false
        self.bytesForwarded = 0
        self.activeConnections = 0
    }

    public static func == (lhs: ProxySession, rhs: ProxySession) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private final class ProxyConnectionPair {
    let id = UUID()
    let inbound: NWConnection
    let outbound: NWConnection
    var idleWorkItem: DispatchWorkItem?
    var isClosed = false
    var finishedDirections = Set<String>()
    var inboundReady = false
    var outboundReady = false

    init(inbound: NWConnection, outbound: NWConnection) {
        self.inbound = inbound
        self.outbound = outbound
    }
}

public final class TCPProxyManager {
    public static let shared = TCPProxyManager()

    private var listeners: [UUID: NWListener] = [:]
    private var connections: [UUID: [UUID: ProxyConnectionPair]] = [:]
    private var sessions: [UUID: ProxySession] = [:]
    private let queue = DispatchQueue(label: "com.portpilot.proxy", qos: .userInitiated)
    private let lock = NSLock()
    private let restrictCustomPolicyToLoopback: Bool

    public var onSessionUpdated: ((ProxySession) -> Void)?
    public var onError: ((UUID, String) -> Void)?
    public var onLog: ((String) -> Void)?

    public init() { restrictCustomPolicyToLoopback = false }

    /// Exercise admission policy without opening a wildcard test listener.
    /// Production custom policies retain their explicit all-interface behavior.
    internal init(loopbackOnlyForTesting: Bool) {
        restrictCustomPolicyToLoopback = loopbackOnlyForTesting
    }

    public func startProxy(
        listenPort: Int, targetHost: String, targetPort: Int,
        accessPolicy: ProxyAccessPolicy = .loopback,
        connectionLimit: Int = 64, idleTimeout: TimeInterval = 300
    ) throws -> ProxySession {
        guard (1...65_535).contains(listenPort) else { throw ProxyError.invalidPort(listenPort) }
        guard (1...65_535).contains(targetPort) else { throw ProxyError.invalidPort(targetPort) }
        guard (1...4_096).contains(connectionLimit) else { throw ProxyError.invalidConnectionLimit(connectionLimit) }
        guard idleTimeout >= 1 else { throw ProxyError.invalidIdleTimeout(idleTimeout) }
        try accessPolicy.validate()

        let port = NWEndpoint.Port(rawValue: UInt16(listenPort))!
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let listener: NWListener
        do {
            switch accessPolicy {
            case .loopback:
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
                listener = try NWListener(using: parameters)
            case .allowedCIDRs:
                if restrictCustomPolicyToLoopback {
                    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
                    listener = try NWListener(using: parameters)
                } else {
                    listener = try NWListener(using: parameters, on: port)
                }
            }
        } catch {
            throw ProxyError.listenerFailed(error.localizedDescription)
        }

        let session = ProxySession(
            listenPort: listenPort, targetHost: targetHost, targetPort: targetPort,
            accessPolicy: accessPolicy, connectionLimit: connectionLimit, idleTimeout: idleTimeout
        )

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.lock.lock()
                guard var readySession = self.sessions[session.id] else {
                    self.lock.unlock()
                    return
                }
                readySession.isActive = true
                self.sessions[session.id] = readySession
                self.lock.unlock()
                DispatchQueue.main.async {
                    self.onSessionUpdated?(readySession)
                    self.onLog?("Proxy listening (\(accessPolicy.displayName)) on port \(listenPort) → \(targetHost):\(targetPort)")
                }
            case .failed(let error):
                DispatchQueue.main.async { self.onError?(session.id, "Listener failed: \(error.localizedDescription)") }
                self.stopProxy(id: session.id)
            case .cancelled:
                DispatchQueue.main.async { self.onLog?("Proxy on port \(listenPort) cancelled") }
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] inbound in
            self?.handleNewConnection(inbound, sessionID: session.id)
        }

        lock.lock()
        sessions[session.id] = session
        connections[session.id] = [:]
        listeners[session.id] = listener
        lock.unlock()
        DispatchQueue.main.async { self.onSessionUpdated?(session) }
        listener.start(queue: queue)
        return session
    }

    public func stopProxy(id: UUID) {
        lock.lock()
        let listener = listeners.removeValue(forKey: id)
        let pairs = Array((connections.removeValue(forKey: id) ?? [:]).values)
        let session = sessions.removeValue(forKey: id)
        for pair in pairs { pair.isClosed = true }
        lock.unlock()

        listener?.cancel()
        for pair in pairs {
            pair.idleWorkItem?.cancel()
            pair.inbound.cancel()
            pair.outbound.cancel()
        }
        if var session {
            session.isActive = false
            session.activeConnections = 0
            DispatchQueue.main.async { self.onSessionUpdated?(session) }
        }
    }

    public func stopAll() {
        lock.lock()
        let ids = Array(sessions.keys)
        lock.unlock()
        for id in ids { stopProxy(id: id) }
    }

    public func getActiveSessions() -> [ProxySession] {
        lock.lock()
        defer { lock.unlock() }
        return Array(sessions.values).filter(\.isActive)
    }

    public func getSession(id: UUID) -> ProxySession? {
        lock.lock()
        defer { lock.unlock() }
        return sessions[id]
    }

    private func handleNewConnection(_ inbound: NWConnection, sessionID: UUID) {
        let remoteAddress: String
        if case .hostPort(let host, _) = inbound.endpoint {
            remoteAddress = String(describing: host)
        } else {
            remoteAddress = ""
        }

        lock.lock()
        guard let session = sessions[sessionID], session.isActive,
              session.accessPolicy.permits(address: remoteAddress),
              (connections[sessionID]?.count ?? session.connectionLimit) < session.connectionLimit else {
            lock.unlock()
            DispatchQueue.main.async { self.onLog?("Rejected proxy client \(remoteAddress.isEmpty ? "unknown" : remoteAddress)") }
            inbound.cancel()
            return
        }

        let targetPort = NWEndpoint.Port(rawValue: UInt16(session.targetPort))!
        let outbound = NWConnection(host: NWEndpoint.Host(session.targetHost), port: targetPort, using: .tcp)
        let pair = ProxyConnectionPair(inbound: inbound, outbound: outbound)
        connections[sessionID]?[pair.id] = pair
        var updated = session
        updated.activeConnections = connections[sessionID]?.count ?? 0
        sessions[sessionID] = updated
        lock.unlock()

        DispatchQueue.main.async {
            self.onLog?("Accepted proxy client \(remoteAddress)")
            self.onSessionUpdated?(updated)
        }
        resetIdleTimer(pair, sessionID: sessionID, timeout: session.idleTimeout)

        inbound.stateUpdateHandler = { [weak self, weak pair] state in
            guard let self, let pair else { return }
            switch state {
            case .ready:
                pair.inboundReady = true
                self.relay(from: pair.inbound, to: pair.outbound, pair: pair, sessionID: sessionID, label: "client→target")
            case .failed, .cancelled:
                // Once ready, outstanding receive/send callbacks own cleanup
                // so a state notification cannot discard buffered final bytes.
                if !pair.inboundReady { self.closePair(pair, sessionID: sessionID) }
            default: break
            }
        }
        outbound.stateUpdateHandler = { [weak self, weak pair] state in
            guard let self, let pair else { return }
            switch state {
            case .ready:
                pair.outboundReady = true
                self.relay(from: pair.outbound, to: pair.inbound, pair: pair, sessionID: sessionID, label: "target→client")
            case .failed, .cancelled:
                if !pair.outboundReady { self.closePair(pair, sessionID: sessionID) }
            default: break
            }
        }

        inbound.start(queue: queue)
        outbound.start(queue: queue)
    }

    private func relay(
        from source: NWConnection, to destination: NWConnection,
        pair: ProxyConnectionPair, sessionID: UUID, label: String
    ) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self, weak pair] data, context, contextComplete, error in
            guard let self, let pair else { return }
            let isComplete = contextComplete && context?.isFinal == true
            if let data, !data.isEmpty {
                self.lock.lock()
                let live = !pair.isClosed && self.connections[sessionID]?[pair.id] != nil
                if live, var session = self.sessions[sessionID] {
                    session.bytesForwarded += UInt64(data.count)
                    self.sessions[sessionID] = session
                }
                self.lock.unlock()
                guard live else { return }
                self.resetIdleTimer(pair, sessionID: sessionID, timeout: self.sessionIdleTimeout(sessionID))
                // Keep all bytes and FIN in one stream context so final EOF
                // cannot be scheduled ahead of previously enqueued messages.
                destination.send(content: data, contentContext: .defaultStream, isComplete: isComplete && error == nil,
                                 completion: .contentProcessed { [weak self, weak pair] sendError in
                    guard let self, let pair else { return }
                    if let sendError {
                        DispatchQueue.main.async { self.onLog?("Send error (\(label)): \(sendError.localizedDescription)") }
                        self.closePair(pair, sessionID: sessionID)
                    } else if let error {
                        DispatchQueue.main.async { self.onLog?("Receive error (\(label)): \(error.localizedDescription)") }
                        self.closePair(pair, sessionID: sessionID)
                    } else if isComplete {
                        self.didFinishDirection(pair, sessionID: sessionID, label: label)
                    } else {
                        self.relay(from: source, to: destination, pair: pair, sessionID: sessionID, label: label)
                    }
                })
            } else if let error {
                DispatchQueue.main.async { self.onLog?("Receive error (\(label)): \(error.localizedDescription)") }
                self.closePair(pair, sessionID: sessionID)
            } else if isComplete {
                self.finishDirection(to: destination, pair: pair, sessionID: sessionID, label: label)
            } else {
                self.relay(from: source, to: destination, pair: pair, sessionID: sessionID, label: label)
            }
        }
    }

    /// TCP EOF closes only this write direction; the peer may still owe a response.
    private func finishDirection(to destination: NWConnection, pair: ProxyConnectionPair,
                                 sessionID: UUID, label: String) {
        destination.send(content: nil, contentContext: .defaultStream, isComplete: true,
                         completion: .contentProcessed { [weak self, weak pair] error in
            guard let self, let pair else { return }
            if error != nil {
                self.closePair(pair, sessionID: sessionID)
                return
            }
            self.didFinishDirection(pair, sessionID: sessionID, label: label)
        })
    }

    private func didFinishDirection(_ pair: ProxyConnectionPair, sessionID: UUID, label: String) {
        lock.lock()
        pair.finishedDirections.insert(label)
        let complete = pair.finishedDirections.count == 2
        lock.unlock()
        if complete { closePair(pair, sessionID: sessionID) }
    }

    private func sessionIdleTimeout(_ sessionID: UUID) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return sessions[sessionID]?.idleTimeout ?? 1
    }

    private func resetIdleTimer(_ pair: ProxyConnectionPair, sessionID: UUID, timeout: TimeInterval) {
        let item = DispatchWorkItem { [weak self, weak pair] in
            guard let self, let pair else { return }
            DispatchQueue.main.async { self.onLog?("Closed idle proxy connection") }
            self.closePair(pair, sessionID: sessionID)
        }
        lock.lock()
        guard !pair.isClosed, connections[sessionID]?[pair.id] != nil else {
            lock.unlock()
            return
        }
        let previous = pair.idleWorkItem
        pair.idleWorkItem = item
        lock.unlock()
        previous?.cancel()
        queue.asyncAfter(deadline: .now() + timeout, execute: item)
    }

    private func closePair(_ pair: ProxyConnectionPair, sessionID: UUID) {
        lock.lock()
        guard !pair.isClosed, connections[sessionID]?.removeValue(forKey: pair.id) != nil else {
            lock.unlock()
            return
        }
        pair.isClosed = true
        pair.idleWorkItem?.cancel()
        var updated = sessions[sessionID]
        if updated != nil {
            updated!.activeConnections = connections[sessionID]?.count ?? 0
            sessions[sessionID] = updated!
        }
        lock.unlock()

        cancelAndRetainUntilCompleted(pair.inbound)
        cancelAndRetainUntilCompleted(pair.outbound)
        if let updated { DispatchQueue.main.async { self.onSessionUpdated?(updated) } }
    }

    private func cancelAndRetainUntilCompleted(_ connection: NWConnection) {
        if case .cancelled = connection.state {
            connection.stateUpdateHandler = nil
            return
        }
        // Network requires callers to retain connection state until cancellation
        // completes; releasing immediately can discard a queued final response.
        connection.stateUpdateHandler = { state in
            if case .cancelled = state { connection.stateUpdateHandler = nil }
        }
        connection.cancel()
    }

    deinit { stopAll() }
}

public enum ProxyError: LocalizedError {
    case invalidPort(Int)
    case invalidConnectionLimit(Int)
    case invalidIdleTimeout(TimeInterval)
    case invalidAccessPolicy(String)
    case listenerFailed(String)
    case connectionFailed(String)
    case sessionNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .invalidPort(let port): return "Invalid port number: \(port)"
        case .invalidConnectionLimit(let limit): return "Invalid proxy connection limit: \(limit)"
        case .invalidIdleTimeout(let timeout): return "Invalid proxy idle timeout: \(timeout)"
        case .invalidAccessPolicy(let reason): return "Invalid proxy access policy: \(reason)"
        case .listenerFailed(let reason): return "Failed to start listener: \(reason)"
        case .connectionFailed(let reason): return "Connection failed: \(reason)"
        case .sessionNotFound(let id): return "Proxy session not found: \(id)"
        }
    }
}

#endif // canImport(Network)
