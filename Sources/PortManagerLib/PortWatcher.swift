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

/// Thread-safe by design: watchedPorts/timer are lock-guarded, polling runs on
/// the internal queue, delegate callbacks hop to main.
public final class PortWatcher: @unchecked Sendable {
    private let portManager: PortManager
    private var watchedPorts: [Int: WatchedPort] = [:]
    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.portkiller.watcher", qos: .utility)
    private let lock = NSLock()
    /// Queue-confined: skips a poll when the previous one (slow lsof) is still running.
    private var pollInProgress = false

    public weak var delegate: PortWatcherDelegate?

    public var pollInterval: TimeInterval = 2.0

    public init(portManager: PortManager) {
        self.portManager = portManager
    }

    deinit {
        stopWatching()
    }

    // MARK: - Watch Management

    public func addPort(_ port: Int, protocolName: String = "tcp") {
        let watchedPort = WatchedPort(port: port, protocolName: protocolName)
        lock.lock()
        watchedPorts[port] = watchedPort
        lock.unlock()

        queue.async { [weak self] in
            self?.checkSinglePort(port: port, protocolName: protocolName)
        }
    }

    public func removePort(_ port: Int) {
        lock.lock()
        watchedPorts.removeValue(forKey: port)
        lock.unlock()
    }

    public func getWatchedPorts() -> [WatchedPort] {
        lock.lock()
        defer { lock.unlock() }
        return Array(watchedPorts.values).sorted { $0.port < $1.port }
    }

    public func getWatchedPort(_ port: Int) -> WatchedPort? {
        lock.lock()
        defer { lock.unlock() }
        return watchedPorts[port]
    }

    // MARK: - Watching Control

    public var isWatching: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timer != nil
    }

    public func startWatching() {
        lock.lock()
        guard timer == nil else {
            lock.unlock()
            return
        }
        lock.unlock()

        let interval = pollInterval
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            // The timer fires on the scheduling runloop (main); the lsof work
            // happens on the watcher queue so the UI never pays for it.
            self?.queue.async { self?.pollPorts() }
        }
        RunLoop.main.add(timer, forMode: .common)

        lock.lock()
        if self.timer == nil {
            self.timer = timer
            lock.unlock()
        } else {
            // Lost a race with another startWatching — keep the existing timer.
            lock.unlock()
            timer.invalidate()
        }

        queue.async { self.pollPorts() }
    }

    public func stopWatching() {
        lock.lock()
        let timer = self.timer
        self.timer = nil
        lock.unlock()
        timer?.invalidate()
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
        queue.async { self.pollPorts() }
    }

    /// Queue-confined. One lsof per watched port per tick.
    private func pollPorts() {
        guard !pollInProgress else { return }
        pollInProgress = true
        defer { pollInProgress = false }

        lock.lock()
        let snapshot = watchedPorts
        lock.unlock()

        for (port, var watchedPort) in snapshot {
            let newState = checkPortStateSync(port: port, protocolName: watchedPort.protocolName)

            let stateChanged = watchedPort.lastKnownState != newState
            watchedPort.lastKnownState = newState
            watchedPort.isWatching = true

            if stateChanged {
                watchedPort.lastStateChange = Date()
                notifyStateChange(newState, forPort: port)
            }

            lock.lock()
            watchedPorts[port] = watchedPort
            lock.unlock()
        }
    }

    /// Queue-confined single-port check (used right after addPort).
    private func checkSinglePort(port: Int, protocolName: String) {
        let state = checkPortStateSync(port: port, protocolName: protocolName)

        lock.lock()
        guard var watchedPort = watchedPorts[port] else {
            lock.unlock()
            return
        }
        let stateChanged = watchedPort.lastKnownState != state
        watchedPort.lastKnownState = state
        watchedPort.isWatching = true

        if stateChanged {
            watchedPort.lastStateChange = Date()
        }

        watchedPorts[port] = watchedPort
        lock.unlock()

        if stateChanged {
            notifyStateChange(state, forPort: port)
        }
    }

    private func notifyStateChange(_ newState: PortState, forPort port: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

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

    private func checkPortStateSync(port: Int, protocolName: String) -> PortState {
        do {
            // Presence-only check — enrichment (ps, proc_pidpath, framework
            // probes per process) is wasted work on this hot 2 s path.
            let processes = try portManager.getListeningProcesses(
                startPort: port, endPort: port, protocolFilter: protocolName, enrich: false
            )
            return processes.isEmpty ? .available : .occupied
        } catch {
            return .unknown
        }
    }

    // MARK: - Wait for Port

    private func stateOnQueue(port: Int, protocolName: String) async -> PortState {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                continuation.resume(returning: self?.checkPortStateSync(port: port, protocolName: protocolName) ?? .unknown)
            }
        }
    }

    public func waitForPort(_ port: Int, protocolName: String = "tcp", timeout: TimeInterval = 60.0) async throws -> Bool {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            if await stateOnQueue(port: port, protocolName: protocolName) == .available {
                return true
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        return false
    }

    public func waitForPortOccupied(_ port: Int, protocolName: String = "tcp", timeout: TimeInterval = 60.0) async throws -> Bool {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            if await stateOnQueue(port: port, protocolName: protocolName) == .occupied {
                return true
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        return false
    }
}
