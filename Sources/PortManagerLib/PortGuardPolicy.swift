import Foundation

/// Revocable per-port authority shared by the main actor and the enforcement
/// queue. Disarm must not wait behind an in-flight TERM-to-KILL attempt.
/// Every access to the generation dictionary is protected by `lock`.
public final class PortGuardEnforcementGate: @unchecked Sendable {
    private let lock = NSLock()
    private var generations: [Int: UUID] = [:]

    public init() {}

    @discardableResult
    public func activate(port: Int) -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let generation = UUID()
        generations[port] = generation
        return generation
    }

    public func invalidate(port: Int) {
        lock.lock()
        defer { lock.unlock() }
        generations.removeValue(forKey: port)
    }

    public func permits(port: Int, generation: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generations[port] == generation
    }
}

/// Pure decision logic for the port guard: which occupants of a guarded
/// port deserve eviction. Kept free of I/O so the semantics are testable.
public enum PortGuardPolicy {
    /// Process incarnations currently holding a guarded port that were not
    /// grandfathered when the guard was armed. PID reuse never inherits trust.
    public static func victims(
        current: [ProcessIdentity],
        grandfathered: Set<ProcessIdentity>
    ) -> [ProcessIdentity] {
        current.filter { candidate in
            !grandfathered.contains {
                $0.pid == candidate.pid
                    && $0.incarnationToken == candidate.incarnationToken
            }
        }
    }
}

/// Queue-confined generation tokens for independent guarded-port lifecycles.
/// Disarming one port cannot invalidate another port's in-flight snapshot.
public struct PortGuardLifecycle: Sendable {
    private var generations: [Int: UInt64] = [:]

    public init() {}

    @discardableResult
    public mutating func begin(port: Int) -> UInt64 {
        let next = generations[port, default: 0] &+ 1
        generations[port] = next
        return next
    }

    public mutating func invalidate(port: Int) {
        _ = begin(port: port)
    }

    public func isCurrent(port: Int, generation: UInt64) -> Bool {
        generations[port] == generation
    }
}

/// Pure baseline lifecycle used by the asynchronous Guard store. A failed
/// snapshot never becomes an empty trusted baseline, and generations are
/// independent per port.
public struct PortGuardBaselineState: Sendable {
    private var lifecycle = PortGuardLifecycle()
    private var baselines: [Int: Set<ProcessIdentity>] = [:]
    private var inFlight: Set<Int> = []

    public init() {}

    @discardableResult
    public mutating func beginSnapshot(port: Int) -> UInt64 {
        let generation = lifecycle.begin(port: port)
        baselines.removeValue(forKey: port)
        inFlight.insert(port)
        return generation
    }

    public mutating func completeSnapshot(
        port: Int,
        generation: UInt64,
        identities: [ProcessIdentity]?
    ) -> Bool {
        guard lifecycle.isCurrent(port: port, generation: generation) else { return false }
        inFlight.remove(port)
        if let identities {
            baselines[port] = Set(identities)
        } else {
            baselines.removeValue(forKey: port)
        }
        return true
    }

    public mutating func disable(port: Int) {
        lifecycle.invalidate(port: port)
        baselines.removeValue(forKey: port)
        inFlight.remove(port)
    }

    public func baseline(for port: Int) -> Set<ProcessIdentity>? {
        baselines[port]
    }

    public func isSnapshotInFlight(for port: Int) -> Bool {
        inFlight.contains(port)
    }
}
