import Foundation

/// Pure decision logic for the port guard: which occupants of a guarded
/// port deserve eviction. Kept free of I/O so the semantics are testable.
public enum PortGuardPolicy {
    /// Pids currently holding a guarded port that were NOT grandfathered
    /// when the guard was armed. Grandfathered pids — whatever held the
    /// port at enable time (or at app launch, for persisted guards) — are
    /// left alone; everyone who binds after that is a squatter.
    public static func victims(currentPids: [Int], grandfathered: Set<Int>) -> [Int] {
        currentPids.filter { !grandfathered.contains($0) }
    }
}
