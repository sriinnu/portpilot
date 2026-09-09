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

/// Tracks cronjob executions triggered manually from PortPilot ("Run Now"), including
/// duration/exit-code history persisted to disk so it survives app restarts.
public final class CronRunManager: @unchecked Sendable {
    public static let shared = CronRunManager()

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

    private var records: [String: CronRunRecord] = [:]
    private var activeProcesses: [String: Process] = [:]
    private let queue = DispatchQueue(label: "com.portpilot.cronrun")
    private let fileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("PortPilot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("cron_run_history.json")

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
        var collected = Data()
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
                activeProcesses[job.id] = process
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
            let output = String(data: collected, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            drainLock.unlock()

            var finished = CronRunRecord()
            self.queue.sync {
                self.activeProcesses.removeValue(forKey: job.id)
                finished = self.records[job.id] ?? CronRunRecord()
                finished.isRunning = false
                finished.lastRunAt = startedAt
                finished.lastDuration = duration
                finished.lastExitCode = proc.terminationStatus
                finished.runCount += 1
                self.records[job.id] = finished
                self.persist()
            }

            let succeeded = proc.terminationStatus == 0
            var message = "\(job.command) \(succeeded ? "completed" : "exited with status \(proc.terminationStatus)") in \(String(format: "%.2f", duration))s"
            if !output.isEmpty {
                message += " — \(output.prefix(200))"
            }

            self.onUpdate?(job.id, finished)
            self.onLog?(message, !succeeded)
        }

        do {
            try process.run()
            return true
        } catch {
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

    /// Terminate a run this manager started. Returns false if nothing was tracked as running.
    /// Kills the whole process tree: `/bin/sh -c "npm run dev"` puts the real
    /// workload two levels below sh, and SIGTERM to sh alone orphans it —
    /// the node server survives and keeps holding the port.
    @discardableResult
    public func stop(jobID: String) -> Bool {
        var process: Process?
        queue.sync { process = activeProcesses[jobID] }
        guard let process else { return false }

        let rootPID = Int(process.processIdentifier)
        guard rootPID > 1 else { return false }

        let tree = Self.processTree(rootPID: rootPID)
        PortManager().killProcess(pids: tree, timeout: 3)
        return true
    }

    /// Direct children of a pid, via pgrep -P (procfs walk on Linux is not
    /// portable enough across the macOS/Linux pair this lib supports).
    private static func children(ofPID pid: Int) -> [Int] {
        let pgrep = ["/usr/bin/pgrep", "/bin/pgrep", "/usr/local/bin/pgrep"]
            .first { FileManager.default.fileExists(atPath: $0) } ?? "/usr/bin/pgrep"
        let output = PortManager().runCommandQuiet(pgrep, arguments: ["-P", String(pid)], timeout: 5)
        return output.split(separator: "\n").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// pid + all descendants, deepest-first order so children get signaled
    /// before (or with) their parents.
    private static func processTree(rootPID: Int) -> [Int] {
        var descendants: [Int] = []
        var visited: Set<Int> = [rootPID]
        var frontier = [rootPID]
        while let pid = frontier.popLast() {
            for child in children(ofPID: pid) where !visited.contains(child) {
                visited.insert(child)
                frontier.append(child)
                descendants.append(child)
            }
        }
        return descendants.reversed() + [rootPID]
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL)
    }
}
