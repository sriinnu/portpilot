import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Run-history for a single cronjob: when it last ran, how long it took, whether it's running now.
public struct CronRunRecord: Codable, Equatable, Sendable {
    public var lastRunAt: Date?
    public var lastDuration: TimeInterval?
    public var lastExitCode: Int32?
    public var runCount: Int = 0
    public var isRunning: Bool = false
}

/// Combined receipt for PortPilot's tracked process tree and its best-effort
/// sweep for an independently scheduled matching command.
public struct CronStopSummary: Equatable, Sendable {
    public let attempted: Bool
    public let stopped: [Int]
    public let unresolved: [Int]
    public let errors: [String]

    public init(results: [ProcessTerminationResult?], errors: [String] = []) {
        let receipts = results.compactMap { $0 }
        attempted = !receipts.isEmpty
        stopped = Array(Set(receipts.flatMap(\.stopped))).sorted()
        unresolved = Array(Set(receipts.flatMap(\.unresolved))).sorted()
        self.errors = errors
    }

    public var isComplete: Bool { attempted && unresolved.isEmpty && errors.isEmpty }
}

/// Tracks cronjob executions triggered manually from PortPilot ("Run Now"), including
/// duration/exit-code history persisted to disk so it survives app restarts.
public final class CronRunManager: @unchecked Sendable {
    public static let shared = CronRunManager(directory: nil)
    static let maxCapturedOutputBytes = 262_144
    static let defaultMaxRuntime: TimeInterval = 3_600

    private let callbacksLock = NSLock()
    private var onUpdateHandler: ((String, CronRunRecord) -> Void)?
    private var onLogHandler: ((String, Bool) -> Void)?

    /// Fired whenever a record changes (run started, finished). Delivered off the main thread.
    public var onUpdate: ((String, CronRunRecord) -> Void)? {
        get { callbacksLock.lock(); defer { callbacksLock.unlock() }; return onUpdateHandler }
        set { callbacksLock.lock(); onUpdateHandler = newValue; callbacksLock.unlock() }
    }

    /// Fired with a human-readable status line + whether it represents a failure.
    public var onLog: ((String, Bool) -> Void)? {
        get { callbacksLock.lock(); defer { callbacksLock.unlock() }; return onLogHandler }
        set { callbacksLock.lock(); onLogHandler = newValue; callbacksLock.unlock() }
    }

    private struct ActiveProcess {
        let process: Process
        var identity: ProcessIdentity?
    }

    private var records: [String: CronRunRecord] = [:]
    private var activeProcesses: [String: ActiveProcess] = [:]
    private var timedOutJobs: Set<String> = []
    private let queue = DispatchQueue(label: "com.portpilot.cronrun")
    private let fileURL: URL
    private let ownsDirectoryPermissions: Bool
    private let maxRuntime: TimeInterval
    private let childPIDProvider: (Int) throws -> [Int]
    private let identityProvider: ([Int]) -> [Int: ProcessIdentity]
    private let identityTerminator: ([ProcessIdentity], Bool, TimeInterval) -> ProcessTerminationResult

    init(
        directory: URL? = nil,
        maxRuntime: TimeInterval = CronRunManager.defaultMaxRuntime,
        childPIDProvider: @escaping (Int) throws -> [Int] = CronRunManager.children,
        identityProvider: @escaping ([Int]) -> [Int: ProcessIdentity] = {
            PortManager().processIdentities(pids: $0)
        },
        identityTerminator: @escaping ([ProcessIdentity], Bool, TimeInterval) -> ProcessTerminationResult = {
            PortManager().terminateProcesses(identities: $0, force: $1, timeout: $2)
        }
    ) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = directory ?? base.appendingPathComponent("PortPilot", isDirectory: true)
        self.ownsDirectoryPermissions = directory == nil
        self.maxRuntime = max(1, maxRuntime)
        self.childPIDProvider = childPIDProvider
        self.identityProvider = identityProvider
        self.identityTerminator = identityTerminator
        fileURL = dir.appendingPathComponent("cron_run_history.json")
        try? SecureFilePermissions.ensurePrivateDirectory(
            dir,
            secureExisting: ownsDirectoryPermissions
        )
        SecureFilePermissions.repairPrivateFileIfPresent(fileURL)

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: CronRunRecord].self, from: data) {
            records = decoded
        }
    }

    public func record(for id: String) -> CronRunRecord {
        queue.sync { records[id] ?? CronRunRecord() }
    }

    public func isRunning(_ id: String) -> Bool {
        queue.sync { activeProcesses[id] != nil }
    }

    /// Launch the job's command immediately. Returns false if it's already running.
    @discardableResult
    public func runNow(job: CronjobEntry) -> Bool {
        // Start draining before launch: a job writing more than the pipe
        // capacity would block on write, never exit, and the termination
        // handler would never fire (isRunning stuck true forever).
        let pipe = Pipe()
        let drainLock = NSLock()
        let drained = DispatchSemaphore(value: 0)
        var collected = BoundedOutputBuffer(limit: Self.maxCapturedOutputBytes)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                drained.signal()
            } else {
                drainLock.lock()
                collected.append(chunk)
                drainLock.unlock()
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", job.command]
        process.standardOutput = pipe
        process.standardError = pipe

        let startedAt = Date()

        // Reserve atomically: check-and-mark in one queue.sync so two concurrent
        // runNow calls for the same job can't both pass the guard and spawn
        // duplicate processes.
        var reserved = false
        queue.sync {
            if activeProcesses[job.id] == nil {
                activeProcesses[job.id] = ActiveProcess(process: process, identity: nil)
                var rec = records[job.id] ?? CronRunRecord()
                rec.isRunning = true
                records[job.id] = rec
                reserved = true
            }
        }
        guard reserved else { return false }

        onUpdate?(job.id, record(for: job.id))
        onLog?("Running now: \(job.command)", false)

        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            let duration = Date().timeIntervalSince(startedAt)

            // Give the drain a beat to catch up after EOF; a grandchild
            // inheriting the pipe can hold it open, so don't wait forever.
            _ = drained.wait(timeout: .now() + 0.25)
            drainLock.lock()
            let output = String(data: collected.data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let outputWasTruncated = collected.wasTruncated
            drainLock.unlock()

            var finished = CronRunRecord()
            var timedOut = false
            self.queue.sync {
                self.activeProcesses.removeValue(forKey: job.id)
                timedOut = self.timedOutJobs.remove(job.id) != nil
                finished = self.records[job.id] ?? CronRunRecord()
                finished.isRunning = false
                finished.lastRunAt = startedAt
                finished.lastDuration = duration
                finished.lastExitCode = proc.terminationStatus
                finished.runCount += 1
                self.records[job.id] = finished
                self.persist()
            }

            let succeeded = proc.terminationStatus == 0 && !timedOut
            let outcome = timedOut ? "timed out after \(String(format: "%.0f", self.maxRuntime))s" : (succeeded ? "completed" : "exited with status \(proc.terminationStatus)")
            var message = "\(job.command) \(outcome) in \(String(format: "%.2f", duration))s"
            if !output.isEmpty {
                message += " — \(output.prefix(200))"
            }
            if outputWasTruncated {
                message += " [output truncated]"
            }

            self.onUpdate?(job.id, finished)
            self.onLog?(message, !succeeded)
        }

        do {
            try process.run()
            // Process.run() duplicates this descriptor into the child. The
            // parent must release its writer so EOF is observable as soon as
            // the child process tree closes its inherited copies.
            try? pipe.fileHandleForWriting.close()
            let rootPID = Int(process.processIdentifier)
            let rootIdentity: ProcessIdentity?
            if rootPID > 1, process.isRunning {
                let captured = identityProvider([rootPID])[rootPID].map(Self.custodyIdentity)
                // A very short command can exit while identity capture is in
                // flight. Never attach a reused PID's identity to its old
                // Foundation Process handle.
                rootIdentity = process.isRunning ? captured : nil
            } else {
                rootIdentity = nil
            }
            queue.sync {
                guard var active = activeProcesses[job.id], active.process === process else { return }
                active.identity = rootIdentity
                activeProcesses[job.id] = active
            }
            if rootIdentity == nil, process.isRunning {
                onLog?("Started \(job.command), but its process identity could not be verified; PortPilot will refuse PID-only Stop", true)
            }

            queue.asyncAfter(deadline: .now() + maxRuntime) { [weak self, weak process] in
                guard let self, let process,
                      let active = self.activeProcesses[job.id],
                      active.process === process else { return }
                self.timedOutJobs.insert(job.id)
                self.onLog?("Stopping \(job.command): maximum runtime reached", true)
                DispatchQueue.global(qos: .utility).async {
                    guard let rootIdentity = active.identity else {
                        self.onLog?(
                            "Timeout stop refused for \(job.command): process identity unavailable",
                            true
                        )
                        return
                    }
                    do {
                        let result = try self.terminateTracked(rootIdentity: rootIdentity)
                        if !result.isComplete {
                            self.onLog?(
                                "Timeout stop incomplete for \(job.command); unresolved pids: \(result.unresolved.map(String.init).joined(separator: ", "))",
                                true
                            )
                        }
                    } catch {
                        self.onLog?("Timeout stop failed for \(job.command): \(error.localizedDescription)", true)
                    }
                }
            }
            return true
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            try? pipe.fileHandleForWriting.close()
            try? pipe.fileHandleForReading.close()
            queue.sync {
                activeProcesses.removeValue(forKey: job.id)
                var rec = records[job.id] ?? CronRunRecord()
                rec.isRunning = false
                records[job.id] = rec
            }
            onUpdate?(job.id, record(for: job.id))
            onLog?("Failed to start \(job.command): \(error.localizedDescription)", true)
            return false
        }
    }

    /// Terminate a run this manager started. Nil means nothing was tracked;
    /// a non-nil receipt must be checked for unresolved pids before reporting
    /// success.
    /// Kills the whole process tree: `/bin/sh -c "npm run dev"` puts the real
    /// workload two levels below sh, and SIGTERM to sh alone orphans it —
    /// the node server survives and keeps holding the port.
    @discardableResult
    public func stop(jobID: String) throws -> ProcessTerminationResult? {
        var active: ActiveProcess?
        queue.sync { active = activeProcesses[jobID] }
        guard let active else { return nil }

        let rootPID = Int(active.process.processIdentifier)
        guard rootPID > 1 else {
            return ProcessTerminationResult(outcomes: [rootPID: .invalidPID])
        }
        guard let rootIdentity = active.identity else {
            return ProcessTerminationResult(outcomes: [rootPID: .identityUnavailable])
        }
        return try terminateTracked(rootIdentity: rootIdentity)
    }

    /// Resolve a tracked process tree to process incarnations before signaling.
    /// A second tree snapshot rejects descendants that exited and had their PID
    /// reused while identities were being captured. Root identity is checked
    /// both before discovery and immediately before the identity-bound kill.
    func terminateTracked(rootIdentity: ProcessIdentity) throws -> ProcessTerminationResult {
        guard let initialRoot = identityProvider([rootIdentity.pid])[rootIdentity.pid] else {
            return ProcessTerminationResult(outcomes: [rootIdentity.pid: .identityUnavailable])
        }
        guard rootIdentity.matches(initialRoot) else {
            return ProcessTerminationResult(outcomes: [rootIdentity.pid: .identityMismatch])
        }

        let firstTree = try processTree(rootPID: rootIdentity.pid)
        let captured = identityProvider(firstTree)
        let secondTree = try processTree(rootPID: rootIdentity.pid)
        let secondSet = Set(secondTree)

        guard let finalRoot = identityProvider([rootIdentity.pid])[rootIdentity.pid] else {
            return ProcessTerminationResult(outcomes: [rootIdentity.pid: .identityUnavailable])
        }
        guard rootIdentity.matches(finalRoot) else {
            return ProcessTerminationResult(outcomes: [rootIdentity.pid: .identityMismatch])
        }

        var unresolved: [Int: ProcessTerminationOutcome] = [:]
        let firstSet = Set(firstTree)
        for pid in firstSet.symmetricDifference(secondSet) where pid != rootIdentity.pid {
            unresolved[pid] = .identityUnavailable
        }

        var identities: [ProcessIdentity] = []
        for pid in firstTree where secondSet.contains(pid) {
            if pid == rootIdentity.pid {
                identities.append(rootIdentity)
            } else if let identity = captured[pid] {
                identities.append(Self.custodyIdentity(identity))
            } else {
                unresolved[pid] = .identityUnavailable
            }
        }

        let terminated = identityTerminator(identities, false, 3)
        unresolved.merge(terminated.outcomes) { _, terminationOutcome in terminationOutcome }
        return ProcessTerminationResult(outcomes: unresolved)
    }

    /// A shell may `exec` the cron command without changing its process
    /// incarnation. PortPilot owns that incarnation, not one executable path.
    private static func custodyIdentity(_ identity: ProcessIdentity) -> ProcessIdentity {
        ProcessIdentity(
            pid: identity.pid,
            startTime: identity.startTime,
            incarnationToken: identity.incarnationToken,
            executablePath: nil,
            user: identity.user
        )
    }

    /// Direct children of a pid, via pgrep -P (procfs walk on Linux is not
    /// portable enough across the macOS/Linux pair this lib supports).
    private static func children(ofPID pid: Int) throws -> [Int] {
        let pgrep = ["/usr/bin/pgrep", "/bin/pgrep", "/usr/local/bin/pgrep"]
            .first { FileManager.default.fileExists(atPath: $0) } ?? "/usr/bin/pgrep"
        let output = try PortManager().runCommand(
            pgrep,
            arguments: ["-P", String(pid)],
            timeout: 5,
            emptyResultExitStatus: 1
        )
        return output.split(separator: "\n").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// pid + all descendants, deepest-first order so children get signaled
    /// before (or with) their parents.
    private func processTree(rootPID: Int) throws -> [Int] {
        var descendants: [Int] = []
        var visited: Set<Int> = [rootPID]
        var frontier = [rootPID]
        while let pid = frontier.popLast() {
            for child in try childPIDProvider(pid) where child > 1 && !visited.contains(child) {
                visited.insert(child)
                frontier.append(child)
                descendants.append(child)
            }
        }
        return descendants.reversed() + [rootPID]
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? SecureFilePermissions.writePrivateData(
            data,
            to: fileURL,
            secureExistingDirectory: ownsDirectoryPermissions
        )
    }
}
