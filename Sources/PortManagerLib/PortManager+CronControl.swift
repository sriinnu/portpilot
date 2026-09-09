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
            let raw = lines[i]
            let indent = String(raw.prefix { $0 == " " || $0 == "\t" })
            var content = raw.trimmingCharacters(in: .whitespaces)
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
            // Keep the user's original indentation — it's their crontab, not ours.
            if paused && !wasPaused {
                lines[i] = "\(indent)\(Self.cronPauseMarker) \(content)"
            } else if !paused && wasPaused {
                lines[i] = "\(indent)\(content)"
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
        // 0600: this file is a copy of the user's crontab; /tmp default perms
        // (0644) would leave it briefly world-readable.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmpURL.path)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let result = runProcess("/usr/bin/crontab", arguments: [tmpURL.path])
        if result.exitStatus != 0 {
            let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let reason = message.isEmpty
                ? (result.timedOut ? "crontab timed out" : "crontab exited with status \(result.exitStatus ?? -1)")
                : message
            throw CronControlError.writeFailed(reason)
        }
    }

    /// Precision-first match of a cron command line against a running
    /// process's `ps -eo command=` line.
    ///
    /// The executable must agree — an absolute path in the cron line has to
    /// match argv[0] exactly (two different `python3`s on disk are different
    /// programs); a bare name matches however it was invoked. And when the
    /// cron command carries arguments, the process must run the same leading
    /// argument tokens: the script path *is* the identity for interpreter
    /// commands. Basename-only matching made this a shotgun before —
    /// `python3 /x/backup.py` killed every python3 on the machine. A miss is
    /// safe (the user can stop it manually); a false positive destroys
    /// unrelated work, so ambiguity always resolves to "no match".
    public static func cronCommand(_ command: String, matchesProcessCommand processCommand: String) -> Bool {
        let targetTokens = command.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let procTokens = processCommand.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let targetExec = targetTokens.first, let procExec = procTokens.first else { return false }

        if targetExec.hasPrefix("/") {
            guard procExec == targetExec else { return false }
        } else {
            guard procExec == targetExec
                || URL(fileURLWithPath: procExec).lastPathComponent == targetExec
            else { return false }
        }

        let targetArgs = Array(targetTokens.dropFirst())
        guard targetArgs.count <= procTokens.count - 1 else { return false }
        return Array(procTokens.dropFirst().prefix(targetArgs.count)) == targetArgs
    }

    /// Find PIDs of processes matching the cron command — same executable and,
    /// when the command has arguments, the same leading argument tokens. See
    /// `cronCommand(_:matchesProcessCommand:)` for the matching contract.
    public func findRunningProcesses(matching command: String) -> [Int] {
        let output = runCommandQuiet("/bin/ps", arguments: ["-eo", "pid=,command="])
        var pids: [Int] = []

        for line in output.components(separatedBy: "\n") {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty else { continue }
            let parts = trimmedLine.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let pid = Int(parts[0]) else { continue }

            if Self.cronCommand(command, matchesProcessCommand: String(parts[1])) {
                pids.append(pid)
            }
        }

        return pids
    }

    /// Best-effort termination of any running processes matching a cron command.
    /// Used as a fallback for jobs the cron daemon started outside of PortPilot.
    /// Returns how many processes actually stopped (not how many were signaled).
    @discardableResult
    public func stopRunningProcesses(matching command: String) -> Int {
        let pids = findRunningProcesses(matching: command)
        guard !pids.isEmpty else { return 0 }
        let survivors = killProcess(pids: pids, timeout: 3)
        return pids.count - survivors.count
    }
}
