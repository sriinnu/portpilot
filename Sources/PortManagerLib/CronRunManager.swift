import Foundation

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

    /// Fired whenever a record changes (run started, finished). Delivered off the main thread.
    public var onUpdate: ((String, CronRunRecord) -> Void)?
    /// Fired with a human-readable status line + whether it represents a failure.
    public var onLog: ((String, Bool) -> Void)?

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
        var alreadyRunning = false
        queue.sync { alreadyRunning = activeProcesses[job.id] != nil }
        guard !alreadyRunning else { return false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", job.command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let startedAt = Date()

        queue.sync {
            var rec = records[job.id] ?? CronRunRecord()
            rec.isRunning = true
            records[job.id] = rec
        }
        onUpdate?(job.id, record(for: job.id))
        onLog?("Running now: \(job.command)", false)

        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            let duration = Date().timeIntervalSince(startedAt)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

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
            queue.sync { activeProcesses[job.id] = process }
            return true
        } catch {
            queue.sync {
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
    @discardableResult
    public func stop(jobID: String) -> Bool {
        var process: Process?
        queue.sync { process = activeProcesses[jobID] }
        guard let process else { return false }
        process.terminate()
        return true
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL)
    }
}
