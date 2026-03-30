import Foundation

#if canImport(Network)
import Network

/// Represents an active proxy session
public struct ProxySession: Identifiable, Hashable {
    public let id: UUID
    public let listenPort: Int
    public let targetHost: String
    public let targetPort: Int
    public let createdAt: Date
    public var isActive: Bool
    public var bytesForwarded: UInt64
    public var activeConnections: Int

    public init(id: UUID = UUID(), listenPort: Int, targetHost: String, targetPort: Int) {
        self.id = id
        self.listenPort = listenPort
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.createdAt = Date()
        self.isActive = false
        self.bytesForwarded = 0
        self.activeConnections = 0
    }

    public static func == (lhs: ProxySession, rhs: ProxySession) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Manages TCP proxy sessions using Network.framework
public final class TCPProxyManager {
    public static let shared = TCPProxyManager()

    private var listeners: [UUID: NWListener] = [:]
    private var connections: [UUID: [(inbound: NWConnection, outbound: NWConnection)]] = [:]
    private let queue = DispatchQueue(label: "com.portpilot.proxy", qos: .userInitiated)
    private let lock = NSLock()

    // Callbacks
    public var onSessionUpdated: ((ProxySession) -> Void)?
    public var onError: ((UUID, String) -> Void)?
    public var onLog: ((String) -> Void)?

    private var sessions: [UUID: ProxySession] = [:]

    public init() {}

    /// Start a new proxy session
    public func startProxy(listenPort: Int, targetHost: String, targetPort: Int) throws -> ProxySession {
        let session = ProxySession(listenPort: listenPort, targetHost: targetHost, targetPort: targetPort)

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        guard let port = NWEndpoint.Port(rawValue: UInt16(listenPort)) else {
            throw ProxyError.invalidPort(listenPort)
        }

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: port)
        } catch {
            throw ProxyError.listenerFailed(error.localizedDescription)
        }

        var activeSession = session
        activeSession.isActive = true

        lock.lock()
        sessions[session.id] = activeSession
        connections[session.id] = []
        lock.unlock()

        listener.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    self.onLog?("Proxy listening on port \(listenPort) \u{2192} \(targetHost):\(targetPort)")
                }
            case .failed(let error):
                DispatchQueue.main.async {
                    self.onError?(session.id, "Listener failed: \(error.localizedDescription)")
                }
                self.stopProxy(id: session.id)
            case .cancelled:
                DispatchQueue.main.async {
                    self.onLog?("Proxy on port \(listenPort) cancelled")
                }
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] inboundConnection in
            self?.handleNewConnection(inboundConnection, session: session, targetHost: targetHost, targetPort: targetPort)
        }

        listener.start(queue: queue)

        lock.lock()
        listeners[session.id] = listener
        lock.unlock()

        DispatchQueue.main.async {
            self.onSessionUpdated?(activeSession)
        }
        return activeSession
    }

    /// Stop a proxy session
    public func stopProxy(id: UUID) {
        lock.lock()
        let listener = listeners.removeValue(forKey: id)
        let conns = connections.removeValue(forKey: id)
        var session = sessions[id]
        lock.unlock()

        listener?.cancel()
        if let conns = conns {
            for pair in conns {
                pair.inbound.cancel()
                pair.outbound.cancel()
            }
        }

        if session != nil {
            session!.isActive = false
            session!.activeConnections = 0
            let updatedSession = session!
            lock.lock()
            sessions.removeValue(forKey: id)
            lock.unlock()
            DispatchQueue.main.async {
                self.onSessionUpdated?(updatedSession)
            }
        } else {
            lock.lock()
            sessions.removeValue(forKey: id)
            lock.unlock()
        }
    }

    /// Stop all proxy sessions
    public func stopAll() {
        lock.lock()
        let ids = Array(listeners.keys)
        lock.unlock()
        for id in ids {
            stopProxy(id: id)
        }
    }

    /// Get all active sessions
    public func getActiveSessions() -> [ProxySession] {
        lock.lock()
        defer { lock.unlock() }
        return Array(sessions.values).filter { $0.isActive }
    }

    /// Get session by ID
    public func getSession(id: UUID) -> ProxySession? {
        lock.lock()
        defer { lock.unlock() }
        return sessions[id]
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ inbound: NWConnection, session: ProxySession, targetHost: String, targetPort: Int) {
        DispatchQueue.main.async {
            self.onLog?("New connection on proxy port \(session.listenPort)")
        }

        let host = NWEndpoint.Host(targetHost)
        guard let port = NWEndpoint.Port(rawValue: UInt16(targetPort)) else {
            DispatchQueue.main.async {
                self.onError?(session.id, "Invalid target port: \(targetPort)")
            }
            inbound.cancel()
            return
        }

        let outbound = NWConnection(host: host, port: port, using: .tcp)

        lock.lock()
        connections[session.id]?.append((inbound: inbound, outbound: outbound))
        lock.unlock()
        updateConnectionCount(session.id)

        inbound.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.relay(from: inbound, to: outbound, sessionId: session.id, label: "client\u{2192}target")
            case .failed, .cancelled:
                outbound.cancel()
                self?.removeConnection(sessionId: session.id, inbound: inbound)
            default:
                break
            }
        }

        outbound.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.relay(from: outbound, to: inbound, sessionId: session.id, label: "target\u{2192}client")
            case .failed, .cancelled:
                inbound.cancel()
                self?.removeConnection(sessionId: session.id, inbound: inbound)
            default:
                break
            }
        }

        inbound.start(queue: queue)
        outbound.start(queue: queue)
    }

    private func relay(from source: NWConnection, to destination: NWConnection, sessionId: UUID, label: String) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.lock.lock()
                if var session = self.sessions[sessionId] {
                    session.bytesForwarded += UInt64(data.count)
                    self.sessions[sessionId] = session
                }
                self.lock.unlock()

                destination.send(content: data, completion: .contentProcessed { sendError in
                    if let sendError = sendError {
                        DispatchQueue.main.async {
                            self.onLog?("Send error (\(label)): \(sendError.localizedDescription)")
                        }
                        source.cancel()
                        destination.cancel()
                        return
                    }
                    self.relay(from: source, to: destination, sessionId: sessionId, label: label)
                })
            }

            if isComplete {
                destination.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in })
                return
            }

            if let error = error {
                DispatchQueue.main.async {
                    self.onLog?("Receive error (\(label)): \(error.localizedDescription)")
                }
                source.cancel()
                destination.cancel()
            }
        }
    }

    private func removeConnection(sessionId: UUID, inbound: NWConnection) {
        lock.lock()
        connections[sessionId]?.removeAll { $0.inbound === inbound }
        lock.unlock()
        updateConnectionCount(sessionId)
    }

    private func updateConnectionCount(_ sessionId: UUID) {
        lock.lock()
        if var session = sessions[sessionId] {
            session.activeConnections = connections[sessionId]?.count ?? 0
            sessions[sessionId] = session
            let updated = session
            lock.unlock()
            DispatchQueue.main.async { [weak self] in
                self?.onSessionUpdated?(updated)
            }
        } else {
            lock.unlock()
        }
    }

    deinit {
        stopAll()
    }
}

// MARK: - Proxy Errors
public enum ProxyError: LocalizedError {
    case invalidPort(Int)
    case listenerFailed(String)
    case connectionFailed(String)
    case sessionNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .invalidPort(let port): return "Invalid port number: \(port)"
        case .listenerFailed(let reason): return "Failed to start listener: \(reason)"
        case .connectionFailed(let reason): return "Connection failed: \(reason)"
        case .sessionNotFound(let id): return "Proxy session not found: \(id)"
        }
    }
}

#endif // canImport(Network)
