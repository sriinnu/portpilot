import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A process incarnation, not merely a reusable PID. The kernel-backed token
/// sharply narrows PID-reuse risk; callers still fail closed when it cannot be
/// read because macOS does not expose an atomic compare-and-signal handle.
public struct ProcessIdentity: Codable, Hashable, Sendable {
    public let pid: Int
    public let startTime: Date
    public let incarnationToken: String
    public let executablePath: String?
    public let user: String

    public init(pid: Int, startTime: Date, incarnationToken: String, executablePath: String?, user: String) {
        self.pid = pid
        self.startTime = startTime
        self.incarnationToken = incarnationToken
        self.executablePath = executablePath
        self.user = user
    }

    public init?(process: PortProcess) {
        guard process.pid > 1,
              let startTime = process.startTime,
              let token = process.processIdentityToken else { return nil }
        self.init(
            pid: process.pid,
            startTime: startTime,
            incarnationToken: token,
            executablePath: process.processPath,
            user: process.user
        )
    }

    public init?(connection: EstablishedConnection) {
        guard connection.pid > 1,
              let startTime = connection.processStartTime,
              let token = connection.processIdentityToken else { return nil }
        self.init(
            pid: connection.pid,
            startTime: startTime,
            incarnationToken: token,
            executablePath: connection.executablePath,
            user: connection.user
        )
    }

    /// Exact incarnation match. Unknown expected path/user fields do not add a
    /// comparison, but the kernel-backed incarnation token is mandatory.
    public func matches(_ current: ProcessIdentity) -> Bool {
        guard pid == current.pid, incarnationToken == current.incarnationToken else { return false }
        if let executablePath, executablePath != current.executablePath { return false }
        if user != "unknown", !user.isEmpty, user != current.user { return false }
        return true
    }
}

public enum ProcessControlSignal: Equatable, Sendable {
    case pause
    case resume

    fileprivate var rawValue: Int32 {
        switch self {
        case .pause: return SIGSTOP
        case .resume: return SIGCONT
        }
    }
}

public enum ProcessSignalOutcome: Equatable, Sendable {
    case delivered
    case invalidPID
    case notFound
    case permissionDenied
    case identityUnavailable
    case identityMismatch
    case failed(errno: Int32)

    public var wasDelivered: Bool { self == .delivered }
}

public enum ProcessTerminationOutcome: Equatable, Sendable {
    case terminated
    case alreadyExited
    case invalidPID
    case permissionDenied
    case identityUnavailable
    case identityMismatch
    case signalFailed(errno: Int32)
    case probeFailed(errno: Int32)
    case survived
    case cancelled

    fileprivate var isComplete: Bool {
        self == .terminated || self == .alreadyExited
    }
}

/// Per-PID termination receipt. Callers must use `isComplete`, rather than
/// inferring success from an empty survivor list.
public struct ProcessTerminationResult: Sendable {
    public let outcomes: [Int: ProcessTerminationOutcome]

    public init(outcomes: [Int: ProcessTerminationOutcome]) {
        self.outcomes = outcomes
    }

    public var requested: [Int] { outcomes.keys.sorted() }
    public var terminated: [Int] { pids(matching: { $0 == .terminated }) }
    public var alreadyExited: [Int] { pids(matching: { $0 == .alreadyExited }) }
    public var stopped: [Int] { pids(matching: \.isComplete) }
    public var survivors: [Int] {
        pids { outcome in
            outcome == .survived || outcome == .permissionDenied
        }
    }
    public var permissionDenied: [Int] { pids(matching: { $0 == .permissionDenied }) }
    public var cancelled: [Int] { pids(matching: { $0 == .cancelled }) }
    public var invalid: [Int] { pids(matching: { $0 == .invalidPID }) }
    public var unknown: [Int] {
        pids { outcome in
            switch outcome {
            case .identityUnavailable, .identityMismatch, .signalFailed, .probeFailed:
                return true
            default:
                return false
            }
        }
    }
    public var unresolved: [Int] { pids { !$0.isComplete } }
    public var isComplete: Bool { unresolved.isEmpty }

    private func pids(matching predicate: (ProcessTerminationOutcome) -> Bool) -> [Int] {
        outcomes.compactMap { predicate($0.value) ? $0.key : nil }.sorted()
    }
}

enum ProcessProbeResult: Equatable {
    case running
    case notFound
    case permissionDenied
    case failed(errno: Int32)
}

enum ProcessSyscallResult: Equatable {
    case success
    case failed(errno: Int32)
}

struct ProcessSignalEnvironment {
    var signal: (Int, Int32) -> ProcessSyscallResult
    var probe: (Int) -> ProcessProbeResult
    var identity: (Int) -> ProcessIdentity?
    var wait: (TimeInterval) -> Void
}

struct ProcessTerminationTarget {
    let pid: Int
    let expectedIdentity: ProcessIdentity
}

enum ProcessEscalationPolicy {
    static func permits(expectedToken: String?, currentToken: String?) -> Bool {
        guard let expectedToken, let currentToken else { return false }
        return expectedToken == currentToken
    }
}

/// Bind a kernel identity only to observations that survive a second raw
/// discovery snapshot. Identity capture by PID alone is insufficient: the
/// original holder can exit and its PID can be reused before enrichment.
enum ProcessObservationBinding {
    private struct ListeningKey: Hashable {
        let pid: Int
        let port: Int
        let protocolName: String
        let user: String
        let command: String

        init(_ process: PortProcess) {
            pid = process.pid
            port = process.port
            protocolName = process.protocolName
            user = process.user
            command = process.command
        }
    }

    private struct ConnectionKey: Hashable {
        let pid: Int
        let localAddress: String
        let remoteAddress: String
        let state: String
        let user: String
        let processName: String

        init(_ connection: EstablishedConnection) {
            pid = connection.pid
            localAddress = connection.localAddress
            remoteAddress = connection.remoteAddress
            state = connection.state
            user = connection.user
            processName = connection.processName
        }
    }

    private struct NamedProcessKey: Hashable {
        let pid: Int
        let user: String
        let command: String

        init(_ process: PortProcess) {
            pid = process.pid
            user = process.user
            command = process.command
        }
    }

    static func listening(
        enriched: [PortProcess],
        confirmed: [PortProcess]
    ) -> [PortProcess] {
        var confirmedCounts = occurrenceCounts(confirmed.map(ListeningKey.init))
        return enriched.map { process in
            guard consume(ListeningKey(process), from: &confirmedCounts) else {
                var unbound = process
                unbound.processIdentityToken = nil
                return unbound
            }
            return process
        }
    }

    /// A Guard baseline is all-or-nothing: both raw snapshots must describe
    /// the same multiset of holders and every holder must have an identity.
    /// This distinguishes a genuinely free port from a holder that appeared
    /// during identity capture.
    static func stableListeningIdentities(
        enriched: [PortProcess],
        confirmed: [PortProcess]
    ) -> [ProcessIdentity]? {
        guard occurrenceCounts(enriched.map(ListeningKey.init))
                == occurrenceCounts(confirmed.map(ListeningKey.init)) else {
            return nil
        }
        let identities = enriched.compactMap(ProcessIdentity.init(process:))
        guard identities.count == enriched.count else { return nil }
        return identities
    }

    static func connections(
        enriched: [EstablishedConnection],
        confirmed: [EstablishedConnection]
    ) -> [EstablishedConnection] {
        var confirmedCounts = occurrenceCounts(confirmed.map(ConnectionKey.init))
        return enriched.map { connection in
            guard consume(ConnectionKey(connection), from: &confirmedCounts) else {
                var unbound = connection
                unbound.processIdentityToken = nil
                return unbound
            }
            return connection
        }
    }

    static func namedProcesses(
        enriched: [PortProcess],
        confirmed: [PortProcess]
    ) -> [PortProcess] {
        var confirmedCounts = occurrenceCounts(confirmed.map(NamedProcessKey.init))
        return enriched.map { process in
            guard consume(NamedProcessKey(process), from: &confirmedCounts) else {
                var unbound = process
                unbound.processIdentityToken = nil
                return unbound
            }
            return process
        }
    }

    private static func occurrenceCounts<Key: Hashable>(_ keys: [Key]) -> [Key: Int] {
        keys.reduce(into: [:]) { counts, key in counts[key, default: 0] += 1 }
    }

    private static func consume<Key: Hashable>(_ key: Key, from counts: inout [Key: Int]) -> Bool {
        guard let count = counts[key], count > 0 else { return false }
        if count == 1 {
            counts.removeValue(forKey: key)
        } else {
            counts[key] = count - 1
        }
        return true
    }
}

/// Syscall-free core. Tests inject every probe/signal/clock edge so no test
/// can accidentally affect a real process.
struct ProcessSignalCore {
    let environment: ProcessSignalEnvironment

    func send(_ signal: ProcessControlSignal, to expected: ProcessIdentity) -> ProcessSignalOutcome {
        guard expected.pid > 1 else { return .invalidPID }
        guard let current = environment.identity(expected.pid) else { return .identityUnavailable }
        guard expected.matches(current) else { return .identityMismatch }

        switch environment.signal(expected.pid, signal.rawValue) {
        case .success:
            return .delivered
        case .failed(let code) where code == ESRCH:
            return .notFound
        case .failed(let code) where code == EPERM:
            return .permissionDenied
        case .failed(let code):
            return .failed(errno: code)
        }
    }

    func terminate(
        _ targets: [ProcessTerminationTarget],
        force: Bool,
        timeout: TimeInterval,
        pollInterval: TimeInterval = 0.1,
        shouldContinue: () -> Bool = { true }
    ) -> ProcessTerminationResult {
        var outcomes: [Int: ProcessTerminationOutcome] = [:]
        var pending: [Int: ProcessIdentity] = [:]

        // First occurrence wins. A PID cannot name two incarnations at once.
        for target in targets where outcomes[target.pid] == nil && pending[target.pid] == nil {
            guard target.pid > 1 else {
                outcomes[target.pid] = .invalidPID
                continue
            }

            switch environment.probe(target.pid) {
            case .notFound:
                outcomes[target.pid] = .alreadyExited
                continue
            case .failed(let code):
                outcomes[target.pid] = .probeFailed(errno: code)
                continue
            case .running, .permissionDenied:
                break // EPERM means the process exists.
            }

            let expected = target.expectedIdentity
            guard let current = environment.identity(target.pid) else {
                outcomes[target.pid] = .identityUnavailable
                continue
            }
            guard expected.matches(current) else {
                outcomes[target.pid] = .identityMismatch
                continue
            }
            guard shouldContinue() else {
                outcomes[target.pid] = .cancelled
                continue
            }

            let initialSignal = force ? SIGKILL : SIGTERM
            switch environment.signal(target.pid, initialSignal) {
            case .success:
                pending[target.pid] = expected
            case .failed(let code) where code == ESRCH:
                outcomes[target.pid] = .alreadyExited
            case .failed(let code) where code == EPERM:
                outcomes[target.pid] = .permissionDenied
            case .failed(let code):
                outcomes[target.pid] = .signalFailed(errno: code)
            }
        }

        if force {
            guard shouldContinue() else {
                cancelPending(&pending, outcomes: &outcomes)
                return ProcessTerminationResult(outcomes: outcomes)
            }
            environment.wait(0.15)
            finishProbing(&pending, outcomes: &outcomes)
            return ProcessTerminationResult(outcomes: outcomes)
        }

        let interval = max(0.01, pollInterval)
        let checks = max(1, Int(ceil(max(0, timeout) / interval)))
        for _ in 0..<checks where !pending.isEmpty {
            guard shouldContinue() else {
                cancelPending(&pending, outcomes: &outcomes)
                break
            }
            environment.wait(interval)
            guard shouldContinue() else {
                cancelPending(&pending, outcomes: &outcomes)
                break
            }
            probeExited(&pending, outcomes: &outcomes)
        }

        // Revalidate identity immediately before escalation. If the original
        // process exited and its PID was reused, never SIGKILL the replacement.
        for (pid, expected) in Array(pending) {
            guard let current = environment.identity(pid) else {
                outcomes[pid] = .identityUnavailable
                pending.removeValue(forKey: pid)
                continue
            }
            guard expected.matches(current) else {
                outcomes[pid] = .identityMismatch
                pending.removeValue(forKey: pid)
                continue
            }
            guard shouldContinue() else {
                outcomes[pid] = .cancelled
                pending.removeValue(forKey: pid)
                continue
            }

            switch environment.signal(pid, SIGKILL) {
            case .success:
                break
            case .failed(let code) where code == ESRCH:
                outcomes[pid] = .terminated
                pending.removeValue(forKey: pid)
            case .failed(let code) where code == EPERM:
                outcomes[pid] = .permissionDenied
                pending.removeValue(forKey: pid)
            case .failed(let code):
                outcomes[pid] = .signalFailed(errno: code)
                pending.removeValue(forKey: pid)
            }
        }

        if !pending.isEmpty {
            environment.wait(0.15)
            finishProbing(&pending, outcomes: &outcomes)
        }
        return ProcessTerminationResult(outcomes: outcomes)
    }

    private func cancelPending(
        _ pending: inout [Int: ProcessIdentity],
        outcomes: inout [Int: ProcessTerminationOutcome]
    ) {
        for pid in pending.keys {
            outcomes[pid] = .cancelled
        }
        pending.removeAll()
    }

    private func probeExited(
        _ pending: inout [Int: ProcessIdentity],
        outcomes: inout [Int: ProcessTerminationOutcome]
    ) {
        for pid in Array(pending.keys) {
            switch environment.probe(pid) {
            case .notFound:
                outcomes[pid] = .terminated
                pending.removeValue(forKey: pid)
            case .failed(let code):
                outcomes[pid] = .probeFailed(errno: code)
                pending.removeValue(forKey: pid)
            case .running, .permissionDenied:
                break
            }
        }
    }

    private func finishProbing(
        _ pending: inout [Int: ProcessIdentity],
        outcomes: inout [Int: ProcessTerminationOutcome]
    ) {
        for pid in Array(pending.keys) {
            switch environment.probe(pid) {
            case .notFound:
                outcomes[pid] = .terminated
            case .running, .permissionDenied:
                outcomes[pid] = .survived
            case .failed(let code):
                outcomes[pid] = .probeFailed(errno: code)
            }
            pending.removeValue(forKey: pid)
        }
    }
}

extension PortManager {
    /// Read current process incarnations in one `ps` snapshot. Missing start
    /// times are omitted: callers that authorize effects must fail closed.
    public func processIdentities(pids: [Int]) -> [Int: ProcessIdentity] {
        let valid = Array(Set(pids.filter { $0 > 1 })).sorted()
        guard !valid.isEmpty else { return [:] }

        #if os(macOS)
        let psPath = "/bin/ps"
        #elseif os(Linux)
        let psPath = "/usr/bin/ps"
        #else
        return [:]
        #endif

        let before = Dictionary(uniqueKeysWithValues: valid.compactMap { pid in
            kernelIncarnation(pid: pid).map { (pid, $0) }
        })

        guard let output = try? runCommand(
            psPath,
            arguments: ["-p", valid.map(String.init).joined(separator: ","), "-o", "pid=,ppid=,user=,lstart=,args="],
            environment: ["LC_ALL": "C"]
        ) else { return [:] }

        var identities: [Int: ProcessIdentity] = [:]
        for line in output.components(separatedBy: "\n") {
            guard let parsed = Self.parsePSLine(line, hasUser: true),
                  valid.contains(parsed.pid),
                  let fallbackStartTime = parsed.startTime,
                  let first = before[parsed.pid] else { continue }
            let executablePath = ProcessClassifier.shared.getProcessPath(pid: parsed.pid)
            guard let second = kernelIncarnation(pid: parsed.pid),
                  first.token == second.token else { continue }

            #if os(macOS)
            // `ps lstart` is rounded to seconds. Reject a mixed observation if
            // its second does not agree with the kernel start timestamp read
            // both before and after the rest of enrichment.
            guard let exactStartTime = first.startTime,
                  Int64(exactStartTime.timeIntervalSince1970.rounded(.down))
                    == Int64(fallbackStartTime.timeIntervalSince1970.rounded(.down)) else { continue }
            let startTime = exactStartTime
            #else
            let startTime = fallbackStartTime
            #endif

            identities[parsed.pid] = ProcessIdentity(
                pid: parsed.pid,
                startTime: startTime,
                incarnationToken: first.token,
                executablePath: executablePath,
                user: parsed.user ?? "unknown"
            )
        }
        return identities
    }

    public func processIdentity(pid: Int) -> ProcessIdentity? {
        processIdentities(pids: [pid])[pid]
    }

    /// Direct kernel/proc token read with no subprocess. Used by the command
    /// runner itself so timeout handling cannot recursively invoke runProcess.
    func processIncarnationToken(pid: Int) -> String? {
        kernelIncarnation(pid: pid)?.token
    }

    private func kernelIncarnation(pid: Int) -> (token: String, startTime: Date?)? {
        #if os(macOS)
        var info = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let readSize = proc_pidinfo(
            Int32(pid),
            PROC_PIDTBSDINFO,
            0,
            &info,
            expectedSize
        )
        guard readSize == expectedSize else { return nil }
        let seconds = info.pbi_start_tvsec
        let microseconds = info.pbi_start_tvusec
        let date = Date(timeIntervalSince1970:
            TimeInterval(seconds) + TimeInterval(microseconds) / 1_000_000
        )
        return ("darwin:\(seconds):\(microseconds)", date)
        #elseif os(Linux)
        // /proc/<pid>/stat field 22 is start time in clock ticks since boot.
        // Split after the final ')' because the command field may contain spaces.
        // procfs reports a zero file size. Read to EOF rather than depending on
        // a Foundation whole-file loader's size-based optimization.
        guard let handle = FileHandle(forReadingAtPath: "/proc/\(pid)/stat") else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.readToEnd(),
              let stat = String(data: data, encoding: .utf8),
              let commandEnd = stat.lastIndex(of: ")") else { return nil }
        let tail = stat[stat.index(after: commandEnd)...]
            .split(whereSeparator: \.isWhitespace)
        guard tail.count > 19 else { return nil }
        return ("linux:\(tail[19])", nil)
        #else
        return nil
        #endif
    }

    /// Capture process incarnations at entry, then use the same compare-and-
    /// signal path as identity-bound callers. Callers with an earlier trusted
    /// observation should still pass those identities directly.
    @discardableResult
    public func terminateProcesses(
        pids: [Int],
        force: Bool = false,
        timeout: TimeInterval = 5,
        shouldContinue: @escaping @Sendable () -> Bool = { true }
    ) -> ProcessTerminationResult {
        let requested = Array(Set(pids)).sorted()
        let valid = requested.filter { $0 > 1 }
        let captured = processIdentities(pids: valid)
        var outcomes: [Int: ProcessTerminationOutcome] = [:]
        for pid in requested where pid <= 1 { outcomes[pid] = .invalidPID }
        for pid in valid where captured[pid] == nil { outcomes[pid] = .identityUnavailable }

        let bound = terminate(
            valid.compactMap { captured[$0] }.map {
                ProcessTerminationTarget(pid: $0.pid, expectedIdentity: $0)
            },
            force: force,
            timeout: timeout,
            shouldContinue: shouldContinue
        )
        outcomes.merge(bound.outcomes) { _, new in new }
        return ProcessTerminationResult(outcomes: outcomes)
    }

    /// Compare-and-signal termination. Every identity is re-read before the
    /// first signal and before TERM-to-KILL escalation.
    @discardableResult
    public func terminateProcesses(
        identities: [ProcessIdentity],
        force: Bool = false,
        timeout: TimeInterval = 5,
        shouldContinue: @escaping @Sendable () -> Bool = { true }
    ) -> ProcessTerminationResult {
        terminate(
            identities.map { ProcessTerminationTarget(pid: $0.pid, expectedIdentity: $0) },
            force: force,
            timeout: timeout,
            shouldContinue: shouldContinue
        )
    }

    @discardableResult
    public func sendControlSignal(
        _ signal: ProcessControlSignal,
        to identity: ProcessIdentity
    ) -> ProcessSignalOutcome {
        ProcessSignalCore(environment: liveSignalEnvironment()).send(signal, to: identity)
    }

    private func terminate(
        _ targets: [ProcessTerminationTarget],
        force: Bool,
        timeout: TimeInterval,
        shouldContinue: @escaping @Sendable () -> Bool = { true }
    ) -> ProcessTerminationResult {
        ProcessSignalCore(environment: liveSignalEnvironment())
            .terminate(
                targets,
                force: force,
                timeout: timeout,
                shouldContinue: shouldContinue
            )
    }

    private func liveSignalEnvironment() -> ProcessSignalEnvironment {
        ProcessSignalEnvironment(
            signal: { pid, signal in
                #if canImport(Darwin) || canImport(Glibc)
                if kill(pid_t(pid), signal) == 0 { return .success }
                return .failed(errno: errno)
                #else
                return .failed(errno: -1)
                #endif
            },
            probe: { pid in
                #if canImport(Darwin) || canImport(Glibc)
                if kill(pid_t(pid), 0) == 0 { return .running }
                switch errno {
                case ESRCH: return .notFound
                case EPERM: return .permissionDenied
                default: return .failed(errno: errno)
                }
                #else
                return .failed(errno: -1)
                #endif
            },
            identity: { [self] pid in processIdentity(pid: pid) },
            wait: { Thread.sleep(forTimeInterval: max(0, $0)) }
        )
    }
}
