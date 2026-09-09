import Foundation

// MARK: - Cronjob Discovery

extension PortManager {

    /// Prefix PortPilot writes into the user's crontab in place of a real line to pause it,
    /// while keeping the original schedule/command intact so resuming is lossless.
    static let cronPauseMarker = "#PORTPILOT_PAUSED#"

    /// Get all cronjobs for the current user and system cron directories
    public func getCronjobs(userOnly: Bool = false, systemOnly: Bool = false) -> [CronjobEntry] {
        var entries: [CronjobEntry] = []

        let platform = Platform.current

        guard platform != .windows else { return [] }

        if !systemOnly {
            let userCrons = getUserCronjobs()
            entries.append(contentsOf: userCrons)
        }

        if !userOnly {
            let systemCrons = getSystemCronjobs()
            entries.append(contentsOf: systemCrons)
        }

        return entries.sorted { ($0.nextRun ?? .distantFuture) < ($1.nextRun ?? .distantFuture) }
    }

    /// Get cronjobs from the current user's crontab
    func getUserCronjobs() -> [CronjobEntry] {
        let output = runCommandQuiet("/usr/bin/crontab", arguments: ["-l"])
        // A personal crontab (crontab -l) never has a user column — only /etc/crontab and
        // /etc/cron.d/* do. Without this, a multi-word command like "/bin/echo hello" gets
        // misparsed as user="/bin/echo" command="hello".
        return parseCrontab(output: output, source: "user", user: currentUsername(), hasUserColumn: false)
    }

    /// Get cronjobs from system cron directories
    func getSystemCronjobs() -> [CronjobEntry] {
        var entries: [CronjobEntry] = []

        if let content = try? String(contentsOfFile: "/etc/crontab", encoding: .utf8) {
            entries.append(contentsOf: parseCrontab(output: content, source: "/etc/crontab", user: nil))
        }

        entries.append(contentsOf: parseCronDirectory("/etc/cron.d/"))
        entries.append(contentsOf: discoverPeriodicCronScripts(in: "/etc/cron.hourly/", schedule: "0 * * * *"))
        entries.append(contentsOf: discoverPeriodicCronScripts(in: "/etc/cron.daily/", schedule: "0 0 * * *"))
        entries.append(contentsOf: discoverPeriodicCronScripts(in: "/etc/cron.weekly/", schedule: "0 0 * * 0"))
        entries.append(contentsOf: discoverPeriodicCronScripts(in: "/etc/cron.monthly/", schedule: "0 0 1 * *"))

        return entries
    }

    private func parseCronDirectory(_ cronPath: String) -> [CronjobEntry] {
        var entries: [CronjobEntry] = []

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: cronPath) else {
            return entries
        }

        for file in files {
            let fullPath = cronPath + file
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }

            if let content = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                entries.append(contentsOf: parseCrontab(output: content, source: fullPath, user: nil))
            }
        }

        return entries
    }

    private func discoverPeriodicCronScripts(in cronPath: String, schedule: String) -> [CronjobEntry] {
        var entries: [CronjobEntry] = []

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: cronPath) else {
            return entries
        }

        let humanReadable = humanReadableSchedule(schedule)

        for file in files {
            let fullPath = cronPath + file
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }
            guard FileManager.default.isExecutableFile(atPath: fullPath) else {
                continue
            }

            entries.append(CronjobEntry(
                command: fullPath,
                schedule: schedule,
                scheduleHuman: humanReadable,
                nextRun: nextCronRun(after: Date(), schedule: schedule),
                user: "root",
                source: fullPath
            ))
        }

        return entries
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
