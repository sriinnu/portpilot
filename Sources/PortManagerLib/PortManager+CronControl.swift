import Foundation

// MARK: - Cronjob Control (pause/resume/stop)

extension PortManager {

    public enum CronControlError: LocalizedError {
        case notEditable
        case notFound
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .notEditable:
                return "Only entries in your personal crontab can be paused or resumed here. System cronjobs are read-only."
            case .notFound:
                return "Couldn't find this cronjob in your crontab anymore — try refreshing."
            case .writeFailed(let message):
                return "Failed to update crontab: \(message)"
            }
        }
    }

    /// Pause a user crontab entry by commenting it out with a PortPilot marker,
    /// leaving the original line recoverable so resuming is lossless.
    public func pauseCronjob(_ job: CronjobEntry) throws {
        try setCronjobPaused(job, paused: true)
    }

    /// Resume a previously paused user crontab entry.
    public func resumeCronjob(_ job: CronjobEntry) throws {
        try setCronjobPaused(job, paused: false)
    }

    private func setCronjobPaused(_ job: CronjobEntry, paused: Bool) throws {
        guard job.isEditable else { throw CronControlError.notEditable }

        let output = runCommandQuiet("/usr/bin/crontab", arguments: ["-l"])
        var lines = output.components(separatedBy: "\n")
        var matched = false

        for i in lines.indices {
            var content = lines[i].trimmingCharacters(in: .whitespaces)
            let wasPaused = content.hasPrefix(Self.cronPauseMarker)
            if wasPaused {
                content = String(content.dropFirst(Self.cronPauseMarker.count)).trimmingCharacters(in: .whitespaces)
            }
            guard !content.isEmpty, !content.hasPrefix("#") || wasPaused else { continue }

            // Only user crontab entries are editable (guarded by job.isEditable above),
            // and a personal crontab never has a user column.
            let candidates = parseCrontab(output: content, source: job.source, user: job.user, hasUserColumn: false)
            guard let candidate = candidates.first, candidate.command == job.command, candidate.schedule == job.schedule else {
                continue
            }

            matched = true
            if paused && !wasPaused {
                lines[i] = "\(Self.cronPauseMarker) \(content)"
            } else if !paused && wasPaused {
                lines[i] = content
            }
            break
        }

        guard matched else { throw CronControlError.notFound }

        try writeCrontab(lines.joined(separator: "\n"))
    }

    private func writeCrontab(_ content: String) throws {
        // macOS's crontab binary silently truncates long file paths (its argument buffer is
        // ~100 bytes), so FileManager's per-app /var/folders/.../T/<uuid> temp path is too long
        // and produces a "No such file or directory" error. /tmp/<short-name> stays well under it.
        let tmpURL = URL(fileURLWithPath: "/tmp/portpilot_cron_\(ProcessInfo.processInfo.processIdentifier)_\(Int(Date().timeIntervalSince1970)).txt")
        try content.write(to: tmpURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/crontab")
        process.arguments = [tmpURL.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw CronControlError.writeFailed(message.isEmpty ? "crontab exited with status \(process.terminationStatus)" : message)
        }
    }

    /// Find PIDs of currently running processes whose command line contains the given cron command.
    public func findRunningProcesses(matching command: String) -> [Int32] {
        let trimmedCommand = command.trimmingCharacters(in: .whitespaces)
        guard !trimmedCommand.isEmpty else { return [] }

        let output = runCommandQuiet("/bin/ps", arguments: ["-eo", "pid=,command="])
        var pids: [Int32] = []

        for line in output.components(separatedBy: "\n") {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty, let spaceIndex = trimmedLine.firstIndex(of: " ") else { continue }

            let pidString = trimmedLine[..<spaceIndex]
            let commandString = trimmedLine[trimmedLine.index(after: spaceIndex)...].trimmingCharacters(in: .whitespaces)

            guard let pid = Int32(pidString), commandString.contains(trimmedCommand) else { continue }
            pids.append(pid)
        }

        return pids
    }

    /// Best-effort termination of any running processes matching a cron command.
    /// Used as a fallback for jobs the cron daemon started outside of PortPilot.
    @discardableResult
    public func stopRunningProcesses(matching command: String) -> Int {
        let pids = findRunningProcesses(matching: command)
        for pid in pids {
            _ = runCommandQuiet("/bin/kill", arguments: ["-TERM", "\(pid)"])
        }
        return pids.count
    }
}
