import Foundation

/// Injectable boundary for a complete crontab transaction. Tests use in-memory
/// fixtures; production supplies checked `crontab` reads and a private temp-file
/// install.
struct CrontabControlIO {
    let read: () throws -> String
    let install: (String) throws -> Void
}

/// Injectable boundary for binding a command match to a process incarnation.
/// The second command snapshot prevents a PID that changed purpose during
/// identity capture from crossing the signal boundary.
struct CronProcessControlIO {
    let matchingPIDs: (String) throws -> [Int]
    let identities: ([Int]) -> [Int: ProcessIdentity]
    let terminate: ([ProcessIdentity], TimeInterval) -> ProcessTerminationResult
}

// MARK: - Cronjob Control (pause/resume/stop)

extension PortManager {

    public enum CronControlError: LocalizedError {
        case notEditable
        case notFound
        case readFailed(String)
        case changedDuringEdit
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .notEditable:
                return "Only entries in your personal crontab can be paused or resumed here. System cronjobs are read-only."
            case .notFound:
                return "Couldn't find this cronjob in your crontab anymore — try refreshing."
            case .readFailed(let message):
                return "Couldn't read a complete crontab: \(message)"
            case .changedDuringEdit:
                return "Your crontab changed while PortPilot was editing it. Nothing was written; refresh and try again."
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
        let lockDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".portpilot", isDirectory: true)
        do {
            try SecureFilePermissions.ensurePrivateDirectory(lockDirectory)
        } catch {
            throw CronControlError.writeFailed("couldn't prepare the private edit lock: \(error.localizedDescription)")
        }

        let io = CrontabControlIO(
            read: { try self.readCrontabChecked() },
            install: { try self.writeCrontab($0) }
        )
        try performCronEdit(
            job: job,
            paused: paused,
            lockURL: lockDirectory.appendingPathComponent("crontab-edit.lock"),
            io: io
        )
    }

    /// Full transaction: serialize PortPilot writers, transform one exact
    /// occurrence, then compare a fresh complete read immediately before the
    /// install. Non-cooperating external editors cannot share our lock, so the
    /// compare is the fail-closed conflict boundary.
    func performCronEdit(
        job: CronjobEntry,
        paused: Bool,
        lockURL: URL,
        io: CrontabControlIO
    ) throws {
        do {
            try FileTransactionLock.withExclusiveLock(at: lockURL) {
                let original = try io.read()
                let updated = try rewrittenCrontab(original, job: job, paused: paused)
                let current = try io.read()
                guard current == original else { throw CronControlError.changedDuringEdit }
                try io.install(updated)
            }
        } catch let error as CronControlError {
            throw error
        } catch {
            throw CronControlError.writeFailed("couldn't lock the crontab edit: \(error.localizedDescription)")
        }
    }

    /// Pure transform used by the transaction and unit tests. Duplicate jobs
    /// use the stable `#2`, `#3`, ... identity assigned by discovery, so acting
    /// on the second identical line cannot rewrite the first.
    func rewrittenCrontab(_ output: String, job: CronjobEntry, paused: Bool) throws -> String {
        var lines = output.components(separatedBy: "\n")
        let targetOccurrence = Self.duplicateOccurrence(for: job)
        var matchingOccurrence = 0

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
            matchingOccurrence += 1
            guard matchingOccurrence == targetOccurrence else { continue }

            // Keep the user's original indentation — it's their crontab, not ours.
            if paused && !wasPaused {
                lines[i] = "\(indent)\(Self.cronPauseMarker) \(content)"
            } else if !paused && wasPaused {
                lines[i] = "\(indent)\(content)"
            }
            return lines.joined(separator: "\n")
        }

        throw CronControlError.notFound
    }

    private static func duplicateOccurrence(for job: CronjobEntry) -> Int {
        let base = "\(job.source):\(job.schedule):\(job.command)"
        guard job.id.hasPrefix(base + "#"),
              let occurrence = Int(job.id.dropFirst(base.count + 1)),
              occurrence > 1 else { return 1 }
        return occurrence
    }

    private func readCrontabChecked() throws -> String {
        let result = runProcess("/usr/bin/crontab", arguments: ["-l"])
        return try Self.checkedCrontabRead(result)
    }

    static func checkedCrontabRead(_ result: CommandOutput) throws -> String {
        if result.timedOut { throw CronControlError.readFailed("crontab -l timed out") }
        if result.outputTruncated { throw CronControlError.readFailed("crontab -l output was truncated") }
        guard let status = result.exitStatus else {
            throw CronControlError.readFailed("crontab -l could not be launched")
        }
        guard status == 0 else {
            let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CronControlError.readFailed(
                detail.isEmpty ? "crontab -l exited with status \(status)" : String(detail.prefix(200))
            )
        }
        return result.output
    }

    private func writeCrontab(_ content: String) throws {
        let tmpURL = try Self.writeSecureTemporaryCrontab(content)
        defer { try? FileManager.default.removeItem(at: tmpURL.deletingLastPathComponent()) }

        let result = runProcess("/usr/bin/crontab", arguments: [tmpURL.path])
        if result.timedOut || result.outputTruncated || result.exitStatus != 0 {
            let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let reason: String
            if result.timedOut {
                reason = "crontab install timed out"
            } else if result.outputTruncated {
                reason = "crontab install output was truncated"
            } else if !message.isEmpty {
                reason = String(message.prefix(200))
            } else if let status = result.exitStatus {
                reason = "crontab exited with status \(status)"
            } else {
                reason = "crontab could not be launched"
            }
            throw CronControlError.writeFailed(reason)
        }
    }

    /// Build a short, private temporary path before writing any crontab data.
    /// A UUID directory avoids predictable-name races; mode 0700 protects the
    /// atomic file write even before its final mode is enforced.
    static func writeSecureTemporaryCrontab(
        _ content: String,
        baseDirectory: URL = URL(fileURLWithPath: "/tmp", isDirectory: true)
    ) throws -> URL {
        let directory = baseDirectory.appendingPathComponent(
            "portpilot-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try SecureFilePermissions.ensurePrivateDirectory(directory)
            let fileURL = directory.appendingPathComponent("crontab.txt")
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            try SecureFilePermissions.enforcePrivateFile(fileURL)
            return fileURL
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
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
        (try? findRunningProcessesChecked(matching: command)) ?? []
    }

    /// Checked variant for destructive Stop. A failed, timed-out, or truncated
    /// process snapshot is unknown and must never be reported as “not running”.
    func findRunningProcessesChecked(matching command: String) throws -> [Int] {
        let output = try runCommand("/bin/ps", arguments: ["-eo", "pid=,command="])
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
    /// Nil means no matching process was observed. Callers that need truthful
    /// status must inspect `isComplete` / `unresolved` on the receipt.
    public func stopRunningProcessesResult(matching command: String) throws -> ProcessTerminationResult? {
        let io = CronProcessControlIO(
            matchingPIDs: { try self.findRunningProcessesChecked(matching: $0) },
            identities: { self.processIdentities(pids: $0) },
            terminate: { self.terminateProcesses(identities: $0, timeout: $1) }
        )
        return try stopRunningProcessesResult(matching: command, io: io)
    }

    func stopRunningProcessesResult(
        matching command: String,
        io: CronProcessControlIO
    ) throws -> ProcessTerminationResult? {
        let observed = Array(Set(try io.matchingPIDs(command).filter { $0 > 1 })).sorted()
        guard !observed.isEmpty else { return nil }

        let captured = io.identities(observed)
        let current = Set(try io.matchingPIDs(command).filter { $0 > 1 })
        let observedSet = Set(observed)
        let confirmed = observed.filter(current.contains)

        var outcomes: [Int: ProcessTerminationOutcome] = [:]
        // A newly observed match was never identity-bound. Refuse to signal it
        // in this transaction and make the incomplete sweep visible to callers.
        for pid in current.subtracting(observedSet) {
            outcomes[pid] = .identityUnavailable
        }

        var identities: [ProcessIdentity] = []
        for pid in confirmed {
            if let identity = captured[pid] {
                identities.append(identity)
            } else {
                outcomes[pid] = .identityUnavailable
            }
        }

        if !identities.isEmpty {
            let terminated = io.terminate(identities, 3)
            outcomes.merge(terminated.outcomes) { _, terminationOutcome in terminationOutcome }
        }

        return outcomes.isEmpty ? nil : ProcessTerminationResult(outcomes: outcomes)
    }

    /// Compatibility count for older callers. Unknown, denied, or surviving
    /// pids are never counted as stopped.
    /// Returns how many processes actually stopped (not how many were signaled).
    @discardableResult
    public func stopRunningProcesses(matching command: String) -> Int {
        (try? stopRunningProcessesResult(matching: command))?.terminated.count ?? 0
    }
}
