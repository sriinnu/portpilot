import Foundation

public struct WatchedPort: Codable, Hashable {
    public let port: Int
    public let protocolName: String
    public var isWatching: Bool
    public var lastKnownState: PortState
    public let watchedAt: Date
    public var lastStateChange: Date?

    public init(port: Int, protocolName: String = "tcp") {
        self.port = port
        self.protocolName = protocolName
        self.isWatching = false
        self.lastKnownState = .unknown
        self.watchedAt = Date()
        self.lastStateChange = nil
    }
}

public enum PortState: String, Codable {
    case available
    case occupied
    case unknown
}

public protocol PortWatcherDelegate: AnyObject {
    func portWatcher(_ watcher: PortWatcher, portBecameAvailable port: Int)
    func portWatcher(_ watcher: PortWatcher, portBecameOccupied port: Int)
    func portWatcher(_ watcher: PortWatcher, didUpdateState state: PortState, forPort port: Int)
}

public final class PortWatcher {
    private let portManager: PortManager
    private var watchedPorts: [Int: WatchedPort] = [:]
    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.portkiller.watcher", qos: .background)

    public weak var delegate: PortWatcherDelegate?

    public var pollInterval: TimeInterval = 2.0
    public var isWatching: Bool { timer != nil }

    public init(portManager: PortManager) {
        self.portManager = portManager
    }

    deinit {
        stopWatching()
    }

    // MARK: - Watch Management

    public func addPort(_ port: Int, protocolName: String = "tcp") {
        let watchedPort = WatchedPort(port: port, protocolName: protocolName)
        watchedPorts[port] = watchedPort

        queue.async { [weak self] in
            self?.checkPortState(port: port, protocol: protocolName)
        }
    }

    public func removePort(_ port: Int) {
        watchedPorts.removeValue(forKey: port)
    }

    public func getWatchedPorts() -> [WatchedPort] {
        return Array(watchedPorts.values).sorted { $0.port < $1.port }
    }

    public func getWatchedPort(_ port: Int) -> WatchedPort? {
        return watchedPorts[port]
    }

    // MARK: - Watching Control

    public func startWatching() {
        guard timer == nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkAllPorts()
        }

        checkAllPorts()
    }

    public func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    public func toggleWatching() {
        if isWatching {
            stopWatching()
        } else {
            startWatching()
        }
    }

    // MARK: - State Checking

    public func checkAllPorts() {
        for (port, var watchedPort) in watchedPorts {
            let newState = checkPortStateSync(port: port, protocolName: watchedPort.protocolName)

            let stateChanged = watchedPort.lastKnownState != newState
            watchedPort.lastKnownState = newState
            watchedPort.isWatching = isWatching

            if stateChanged {
                watchedPort.lastStateChange = Date()

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }

                    switch newState {
                    case .available:
                        self.delegate?.portWatcher(self, portBecameAvailable: port)
                    case .occupied:
                        self.delegate?.portWatcher(self, portBecameOccupied: port)
                    case .unknown:
                        break
                    }

                    self.delegate?.portWatcher(self, didUpdateState: newState, forPort: port)
                }
            }

            watchedPorts[port] = watchedPort
        }
    }

    private func checkPortState(port: Int, protocol proto: String) {
        let state = checkPortStateSync(port: port, protocolName: proto)

        if var watchedPort = watchedPorts[port] {
            let stateChanged = watchedPort.lastKnownState != state
            watchedPort.lastKnownState = state
            watchedPort.isWatching = isWatching

            if stateChanged {
                watchedPort.lastStateChange = Date()
            }

            watchedPorts[port] = watchedPort

            if stateChanged {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.portWatcher(self, didUpdateState: state, forPort: port)
                }
            }
        }
    }

    private func checkPortStateSync(port: Int, protocolName: String) -> PortState {
        do {
            let processes = try portManager.getListeningProcesses(startPort: port, endPort: port, protocolFilter: protocolName)
            return processes.isEmpty ? .available : .occupied
        } catch {
            return .unknown
        }
    }

    // MARK: - Wait for Port

    public func waitForPort(_ port: Int, protocolName: String = "tcp", timeout: TimeInterval = 60.0) async throws -> Bool {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            let state = checkPortStateSync(port: port, protocolName: protocolName)

            if state == .available {
                return true
            }

            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        return false
    }

    public func waitForPortOccupied(_ port: Int, protocolName: String = "tcp", timeout: TimeInterval = 60.0) async throws -> Bool {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            let state = checkPortStateSync(port: port, protocolName: protocolName)

            if state == .occupied {
                return true
            }

            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        return false
    }
}
