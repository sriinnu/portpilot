import Foundation

// MARK: - Cronjob Discovery

public struct CronDiscoverySnapshot: Sendable {
    public let entries: [CronjobEntry]
    public let errors: [String]

    public init(entries: [CronjobEntry], errors: [String] = []) {
        self.entries = entries
        self.errors = errors
    }

    public var isComplete: Bool { errors.isEmpty }
    public var errorDescription: String { errors.joined(separator: "; ") }

    public func requireComplete() throws -> [CronjobEntry] {
        guard isComplete else { throw CronDiscoveryError.incomplete(errors) }
        return entries
    }
}

public enum CronDiscoveryError: LocalizedError, Sendable {
    case source(String)
    case incomplete([String])

    public var errorDescription: String? {
        switch self {
        case .source(let message):
            return message
        case .incomplete(let errors):
            return "Cronjob discovery is incomplete: \(errors.joined(separator: "; "))"
        }
    }
}

private struct CronSourceDiscovery {
    var entries: [CronjobEntry] = []
    var errors: [String] = []
}

extension PortManager {

    /// Prefix PortPilot writes into the user's crontab in place of a real line to pause it,
    /// while keeping the original schedule/command intact so resuming is lossless.
    static let cronPauseMarker = "#PORTPILOT_PAUSED#"

    /// Checked projection retained for API compatibility. Incomplete reads throw.
    public func getCronjobs(userOnly: Bool = false, systemOnly: Bool = false) throws -> [CronjobEntry] {
        try getCronjobSnapshot(userOnly: userOnly, systemOnly: systemOnly).requireComplete()
    }

    /// Read cron sources without converting failures into a successful empty list.
    public func getCronjobSnapshot(userOnly: Bool = false, systemOnly: Bool = false) -> CronDiscoverySnapshot {
        guard !(userOnly && systemOnly) else {
            return CronDiscoverySnapshot(
                entries: [],
                errors: ["Conflicting cron filters: user-only and system-only cannot both be enabled"]
            )
        }

        var entries: [CronjobEntry] = []
        var errors: [String] = []

        let platform = Platform.current

        guard platform != .windows else { return CronDiscoverySnapshot(entries: []) }

        if !systemOnly {
            let user = discoverUserCronjobs()
            entries.append(contentsOf: user.entries)
            errors.append(contentsOf: user.errors)
        }

        if !userOnly {
            let system = discoverSystemCronjobs()
            entries.append(contentsOf: system.entries)
            errors.append(contentsOf: system.errors)
        }

        entries.sort { ($0.nextRun ?? .distantFuture) < ($1.nextRun ?? .distantFuture) }
        return CronDiscoverySnapshot(entries: entries, errors: errors)
    }

    /// Get cronjobs from the current user's crontab
    private func discoverUserCronjobs() -> CronSourceDiscovery {
        let result = runProcess(
            "/usr/bin/crontab",
            arguments: ["-l"],
            environment: ["LC_ALL": "C"]
        )
        let output: String
        do {
            output = try Self.checkedCronDiscoveryRead(result)
        } catch {
            return CronSourceDiscovery(errors: ["user crontab: \(error.localizedDescription)"])
        }
        // A personal crontab (crontab -l) never has a user column — only /etc/crontab and
        // /etc/cron.d/* do. Without this, a multi-word command like "/bin/echo hello" gets
        // misparsed as user="/bin/echo" command="hello".
        return CronSourceDiscovery(entries: parseCrontab(
            output: output,
            source: "user",
            user: currentUsername(),
            hasUserColumn: false
        ))
    }

    static func checkedCronDiscoveryRead(_ result: CommandOutput) throws -> String {
        if result.timedOut {
            throw CronDiscoveryError.source("crontab -l timed out")
        }
        if result.outputTruncated {
            throw CronDiscoveryError.source("crontab -l output was truncated")
        }
        guard let status = result.exitStatus else {
            throw CronDiscoveryError.source("crontab -l could not be launched")
        }
        if status == 0 { return result.output }

        let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if status == 1, detail.lowercased().contains("no crontab for") {
            return ""
        }
        let message = detail.isEmpty
            ? "crontab -l exited with status \(status)"
            : String(detail.prefix(200))
        throw CronDiscoveryError.source(message)
    }

    /// Get cronjobs from system cron directories while retaining per-source errors.
    private func discoverSystemCronjobs() -> CronSourceDiscovery {
        var result = CronSourceDiscovery()
        let manager = FileManager.default

        if manager.fileExists(atPath: "/etc/crontab") {
            do {
                let content = try String(contentsOfFile: "/etc/crontab", encoding: .utf8)
                result.entries.append(contentsOf: parseCrontab(output: content, source: "/etc/crontab", user: nil))
            } catch {
                result.errors.append("/etc/crontab: \(error.localizedDescription)")
            }
        }

        let cronDirectory = discoverCronDirectory("/etc/cron.d/")
        result.entries.append(contentsOf: cronDirectory.entries)
        result.errors.append(contentsOf: cronDirectory.errors)

        for (path, schedule) in [
            ("/etc/cron.hourly/", "0 * * * *"),
            ("/etc/cron.daily/", "0 0 * * *"),
            ("/etc/cron.weekly/", "0 0 * * 0"),
            ("/etc/cron.monthly/", "0 0 1 * *"),
        ] {
            let periodic = discoverPeriodicCronScripts(in: path, schedule: schedule)
            result.entries.append(contentsOf: periodic.entries)
            result.errors.append(contentsOf: periodic.errors)
        }
        return result
    }

    private func discoverCronDirectory(_ cronPath: String) -> CronSourceDiscovery {
        var result = CronSourceDiscovery()
        let manager = FileManager.default
        guard manager.fileExists(atPath: cronPath) else { return result }

        let files: [String]
        do {
            files = try manager.contentsOfDirectory(atPath: cronPath)
        } catch {
            result.errors.append("\(cronPath): \(error.localizedDescription)")
            return result
        }

        for file in files {
            let fullPath = URL(fileURLWithPath: cronPath, isDirectory: true)
                .appendingPathComponent(file).path
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: fullPath, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }

            do {
                let content = try String(contentsOfFile: fullPath, encoding: .utf8)
                result.entries.append(contentsOf: parseCrontab(output: content, source: fullPath, user: nil))
            } catch {
                result.errors.append("\(fullPath): \(error.localizedDescription)")
            }
        }

        return result
    }

    private func discoverPeriodicCronScripts(in cronPath: String, schedule: String) -> CronSourceDiscovery {
        var result = CronSourceDiscovery()
        let manager = FileManager.default
        guard manager.fileExists(atPath: cronPath) else { return result }

        let files: [String]
        do {
            files = try manager.contentsOfDirectory(atPath: cronPath)
        } catch {
            result.errors.append("\(cronPath): \(error.localizedDescription)")
            return result
        }

        let humanReadable = humanReadableSchedule(schedule)

        for file in files {
            let fullPath = URL(fileURLWithPath: cronPath, isDirectory: true)
                .appendingPathComponent(file).path
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: fullPath, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }
            guard manager.isExecutableFile(atPath: fullPath) else {
                continue
            }

            result.entries.append(CronjobEntry(
                command: fullPath,
                schedule: schedule,
                scheduleHuman: humanReadable,
                nextRun: nextCronRun(after: Date(), schedule: schedule),
                user: "root",
                source: fullPath
            ))
        }

        return result
    }
    /// `@macro` schedules and their five-field equivalents. `@reboot` has none.
    static let cronMacroSchedules: [String: String] = [
        "@yearly": "0 0 1 1 *",
        "@annually": "0 0 1 1 *",
        "@monthly": "0 0 1 * *",
        "@weekly": "0 0 * * 0",
        "@daily": "0 0 * * *",
        "@midnight": "0 0 * * *",
        "@hourly": "0 * * * *",
    ]

    /// Parse crontab output into CronjobEntry objects.
    /// - Parameter hasUserColumn: true for system crontabs (`/etc/crontab`, `/etc/cron.d/*`),
    ///   which include a user field between the schedule and the command; false for a personal
    ///   crontab (`crontab -l`), which never does.
    func parseCrontab(output: String, source: String, user: String?, hasUserColumn: Bool = true) -> [CronjobEntry] {
        var entries: [CronjobEntry] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            var isPaused = false
            if trimmed.hasPrefix(Self.cronPauseMarker) {
                isPaused = true
                trimmed = String(trimmed.dropFirst(Self.cronPauseMarker.count)).trimmingCharacters(in: .whitespaces)
            }
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") || isPaused else { continue }

            let components = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

            // @macro form: "@daily /bin/do-thing" — no five-field schedule.
            // Without this branch the ≥6-token filter silently dropped every
            // macro job. System crontabs still carry the user column
            // ("@daily root /bin/do-thing"), so honor hasUserColumn here too.
            if components[0].hasPrefix("@") {
                let macro = components[0]
                let effectiveUser: String?
                let command: String
                if hasUserColumn, components.count >= 3 {
                    effectiveUser = components[1]
                    command = components.dropFirst(2).joined(separator: " ")
                } else {
                    effectiveUser = user
                    command = components.dropFirst().joined(separator: " ")
                }
                guard !command.isEmpty else { continue }

                if macro == "@reboot" {
                    entries.append(CronjobEntry(
                        command: command, schedule: "@reboot", scheduleHuman: "At reboot",
                        nextRun: nil, user: effectiveUser, source: source, isPaused: isPaused
                    ))
                } else if let schedule = Self.cronMacroSchedules[macro] {
                    entries.append(CronjobEntry(
                        command: command, schedule: schedule,
                        scheduleHuman: humanReadableSchedule(schedule),
                        nextRun: isPaused ? nil : nextCronRun(after: Date(), schedule: schedule),
                        user: effectiveUser, source: source, isPaused: isPaused
                    ))
                }
                continue
            }

            guard components.count >= 6 else { continue }

            let scheduleWords = Array(components[0..<5])
            let command: String
            let effectiveUser: String?

            if hasUserColumn {
                effectiveUser = components[5]
                command = components.dropFirst(6).joined(separator: " ")
            } else {
                command = components.dropFirst(5).joined(separator: " ")
                effectiveUser = user
            }

            guard !command.isEmpty else { continue }

            let schedule = scheduleWords.joined(separator: " ")
            let humanReadable = humanReadableSchedule(schedule)
            // A paused job won't actually fire, so it has no meaningful next-run time.
            let nextRunDate = isPaused ? nil : nextCronRun(after: Date(), schedule: schedule)

            entries.append(CronjobEntry(
                command: command,
                schedule: schedule,
                scheduleHuman: humanReadable,
                nextRun: nextRunDate,
                user: effectiveUser,
                source: source,
                isPaused: isPaused
            ))
        }

        // Identical lines repeated in one crontab would collide on
        // source:schedule:command and confuse ForEach — suffix the second
        // and later occurrences. In-file order is stable, so a duplicate's
        // suffix survives refreshes.
        var idCounts: [String: Int] = [:]
        for i in entries.indices {
            let base = "\(entries[i].source):\(entries[i].schedule):\(entries[i].command)"
            idCounts[base, default: 0] += 1
            let occurrence = idCounts[base]!
            if occurrence > 1 {
                entries[i] = CronjobEntry(
                    command: entries[i].command,
                    schedule: entries[i].schedule,
                    scheduleHuman: entries[i].scheduleHuman,
                    nextRun: entries[i].nextRun,
                    user: entries[i].user,
                    source: entries[i].source,
                    isPaused: entries[i].isPaused,
                    duplicateIndex: occurrence
                )
            }
        }

        return entries
    }

    /// Get current username
    func currentUsername() -> String {
        return ProcessInfo.processInfo.userName
    }

    /// Convert a cron schedule to human-readable format
    func humanReadableSchedule(_ schedule: String) -> String {
        let parts = schedule.split(separator: " ").map(String.init)
        guard parts.count >= 5 else { return schedule }

        let min = parts[0], hour = parts[1], dom = parts[2], month = parts[3], dow = parts[4]

        if min == "*" && hour == "*" && dom == "*" && month == "*" && dow == "*" {
            return "Every minute"
        }

        if min.hasPrefix("*/") {
            let interval = String(min.dropFirst(2))
            return "Every \(interval) min"
        }

        if min == "0" && hour.hasPrefix("*/") {
            let interval = String(hour.dropFirst(2))
            return "Every \(interval)h"
        }

        if min != "*" && hour != "*" && dom == "*" && month == "*" && dow == "*" {
            return "Daily @ \(pad2(hour)):\(pad2(min))"
        }

        if dom == "*" && month == "*" && dow != "*" {
            let dayName = dayOfWeekName(dow)
            return "Weekly on \(dayName) @ \(pad2(hour)):\(pad2(min))"
        }

        if dom != "*" && month == "*" && dow == "*" {
            return "Monthly on day \(dom) @ \(pad2(hour)):\(pad2(min))"
        }

        return schedule
    }

    /// Zero-pad a numeric cron field to 2 ("8" → "08"). Non-numeric patterns
    /// (steps, ranges) pass through — `padding(toLength:withPad:)` *appends*
    /// the pad char, which turned 8:30 into "80:30".
    private func pad2(_ field: String) -> String {
        guard let n = Int(field) else { return field }
        return String(format: "%02d", n)
    }

    /// Get day of week name from number
    func dayOfWeekName(_ dow: String) -> String {
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        // Cron accepts both 0 and 7 for Sunday.
        if let num = Int(dow), num >= 0, num <= 7 {
            return days[num % 7]
        }
        return dow
    }

    /// Calculate the next run date from a cron expression
    public func nextCronRun(after date: Date, schedule: String) -> Date? {
        let parts = schedule.split(separator: " ").map(String.init)
        guard parts.count >= 5 else { return nil }

        let calendar = Calendar.current
        let minPart = parts[0]
        let hourPart = parts[1]
        let domPart = parts[2]
        let monthPart = parts[3]
        let dowPart = parts[4]

        let allowedMinutes = parseCronFieldValues(minPart, min: 0, max: 59)
        let allowedHours = parseCronFieldValues(hourPart, min: 0, max: 23)
        let allowedMonths = Set(parseCronFieldValues(monthPart, min: 1, max: 12))
        let allowedDoms = Set(parseCronFieldValues(domPart, min: 1, max: 31))
        // Cron dow: 0 and 7 both mean Sunday; Calendar.weekday is 1=Sun…7=Sat.
        let allowedDows = Set(parseCronFieldValues(dowPart, min: 0, max: 7).map { $0 % 7 })
        let domRestricted = domPart != "*"
        let dowRestricted = dowPart != "*"

        guard !allowedMinutes.isEmpty, !allowedHours.isEmpty, !allowedMonths.isEmpty,
              !allowedDoms.isEmpty, !allowedDows.isEmpty else {
            return nil
        }

        guard let searchStart = calendar.date(byAdding: .minute, value: 1, to: date) else {
            return nil
        }

        let startComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: searchStart)
        guard
            let normalizedStart = calendar.date(from: startComponents),
            let startHour = startComponents.hour,
            let startMinute = startComponents.minute
        else {
            return nil
        }

        let startDay = calendar.startOfDay(for: normalizedStart)
        let maxDaysToSearch = 366

        for dayOffset in 0..<maxDaysToSearch {
            guard let candidateDay = calendar.date(byAdding: .day, value: dayOffset, to: startDay) else {
                continue
            }

            let dayComponents = calendar.dateComponents([.year, .month, .day, .weekday], from: candidateDay)
            guard
                let year = dayComponents.year,
                let month = dayComponents.month,
                let day = dayComponents.day
            else {
                continue
            }

            guard allowedMonths.contains(month) else { continue }

            let domOK = allowedDoms.contains(day)
            let dowOK = allowedDows.contains((dayComponents.weekday ?? 1) - 1)

            // Vixie cron: when both dom and dow are restricted, a day matching
            // EITHER fires ("0 0 13 * 5" = the 13th AND every Friday).
            let dayMatches = (domRestricted && dowRestricted) ? (domOK || dowOK) : (domOK && dowOK)
            if !dayMatches { continue }

            let isStartDay = calendar.isDate(candidateDay, inSameDayAs: normalizedStart)

            for hour in allowedHours {
                if isStartDay && hour < startHour { continue }

                let minimumMinute = (isStartDay && hour == startHour) ? startMinute : 0
                guard let minute = allowedMinutes.first(where: { $0 >= minimumMinute }) else {
                    continue
                }

                var finalComponents = DateComponents()
                finalComponents.year = year
                finalComponents.month = month
                finalComponents.day = day
                finalComponents.hour = hour
                finalComponents.minute = minute
                finalComponents.second = 0

                if let nextRun = calendar.date(from: finalComponents) {
                    return nextRun
                }
            }
        }

        return nil
    }

    /// Parse a cron field into sorted allowed values (supports *, */n, n, n-m, n,m)
    func parseCronFieldValues(_ pattern: String, min: Int, max: Int) -> [Int] {
        guard min <= max else { return [] }

        if pattern == "*" {
            return Array(min...max)
        }

        if pattern.contains(",") {
            let listParts = pattern.split(separator: ",").map(String.init)
            let values = Set(listParts.flatMap { parseCronFieldValues($0, min: min, max: max) })
            return values.sorted()
        }

        if pattern.hasPrefix("*/") {
            guard let step = Int(String(pattern.dropFirst(2))), step > 0 else { return [] }
            return stride(from: min, through: max, by: step).map { $0 }
        }

        if pattern.contains("-") {
            let rangeParts = pattern.split(separator: "-").map(String.init)
            guard rangeParts.count == 2,
                  let lowerBound = Int(rangeParts[0]),
                  let upperBound = Int(rangeParts[1]) else {
                return []
            }

            let clampedLowerBound = Swift.max(lowerBound, min)
            let clampedUpperBound = Swift.min(upperBound, max)
            guard clampedLowerBound <= clampedUpperBound else { return [] }

            return Array(clampedLowerBound...clampedUpperBound)
        }

        if let intValue = Int(pattern), intValue >= min, intValue <= max {
            return [intValue]
        }

        return []
    }
    /// Match a cron field value against a pattern (supports *, */n, n, n-m, n,m)
    func matchesCronField(_ value: Int, pattern: String) -> Bool {
        if pattern == "*" { return true }

        if pattern.hasPrefix("*/") {
            if let step = Int(String(pattern.dropFirst(2))), step > 0 {
                return value % step == 0
            }
            return false
        }

        if pattern.contains("-") {
            let rangeParts = pattern.split(separator: "-").map(String.init)
            if rangeParts.count == 2, let min = Int(rangeParts[0]), let max = Int(rangeParts[1]) {
                return value >= min && value <= max
            }
        }

        if pattern.contains(",") {
            let listParts = pattern.split(separator: ",").map { String($0) }
            for part in listParts {
                if matchesCronField(value, pattern: part) { return true }
            }
            return false
        }

        if let intValue = Int(pattern) {
            return value == intValue
        }

        return false
    }
}
