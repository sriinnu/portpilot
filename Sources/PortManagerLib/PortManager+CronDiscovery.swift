import Foundation

// MARK: - Cronjob Discovery

extension PortManager {

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
        return parseCrontab(output: output, source: "user", user: currentUsername())
    }

    /// Get cronjobs from system cron directories
    func getSystemCronjobs() -> [CronjobEntry] {
        var entries: [CronjobEntry] = []

        let cronDirs = ["/etc/crontab", "/etc/cron.d/", "/etc/cron.hourly/", "/etc/cron.daily/", "/etc/cron.weekly/", "/etc/cron.monthly/"]

        for cronPath in cronDirs {
            if cronPath.hasSuffix("/") {
                if let files = try? FileManager.default.contentsOfDirectory(atPath: cronPath) {
                    for file in files {
                        let fullPath = cronPath + file
                        if let content = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                            let source = fullPath
                            entries.append(contentsOf: parseCrontab(output: content, source: source, user: extractUserFromCrontab(fullPath: fullPath, line: nil)))
                        }
                    }
                }
            } else {
                if let content = try? String(contentsOfFile: cronPath, encoding: .utf8) {
                    entries.append(contentsOf: parseCrontab(output: content, source: cronPath, user: extractUserFromCrontab(fullPath: cronPath, line: nil)))
                }
            }
        }

        return entries
    }

    /// Parse crontab output into CronjobEntry objects
    func parseCrontab(output: String, source: String, user: String?) -> [CronjobEntry] {
        var entries: [CronjobEntry] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard !trimmed.hasPrefix("#") else { continue }

            let components = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

            var scheduleWords: [String]
            var command: String
            var effectiveUser: String?

            if components.count >= 7 {
                scheduleWords = Array(components[0..<5])
                effectiveUser = components[5]
                command = components.dropFirst(6).joined(separator: " ")
            } else if components.count >= 6 {
                scheduleWords = Array(components[0..<5])
                command = components.dropFirst(5).joined(separator: " ")
                effectiveUser = user
            } else if components.count == 5 {
                continue
            } else {
                continue
            }

            let schedule = scheduleWords.joined(separator: " ")
            let humanReadable = humanReadableSchedule(schedule)
            let nextRunDate = nextCronRun(after: Date(), schedule: schedule)

            entries.append(CronjobEntry(
                command: command,
                schedule: schedule,
                scheduleHuman: humanReadable,
                nextRun: nextRunDate,
                user: effectiveUser,
                source: source
            ))
        }

        return entries
    }

    /// Extract username from a system crontab file header
    func extractUserFromCrontab(fullPath: String, line: String?) -> String? {
        if fullPath == "/etc/crontab" {
            if let content = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                let lines = content.components(separatedBy: "\n")
                for l in lines {
                    let trimmed = l.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                    let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                    if parts.count >= 6 {
                        return parts[5]
                    }
                }
            }
        }
        return nil
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
            return "Daily @ \(hour):\(min.padding(toLength: 2, withPad: "0", startingAt: 0))"
        }

        if dom == "*" && month == "*" && dow != "*" {
            let dayName = dayOfWeekName(dow)
            return "Weekly on \(dayName) @ \(hour):\(min.padding(toLength: 2, withPad: "0", startingAt: 0))"
        }

        if dom != "*" && month == "*" && dow == "*" {
            return "Monthly on day \(dom) @ \(hour):\(min.padding(toLength: 2, withPad: "0", startingAt: 0))"
        }

        return schedule
    }

    /// Get day of week name from number
    func dayOfWeekName(_ dow: String) -> String {
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        if let num = Int(dow), num >= 0, num < 7 {
            return days[num]
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

        var current = date
        let maxIterations = 525600

        for _ in 0..<maxIterations {
            current = calendar.date(byAdding: .minute, value: 1, to: current)!

            let components = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: current)

            guard let min = components.minute, matchesCronField(min, pattern: minPart) else { continue }
            guard let hour = components.hour, matchesCronField(hour, pattern: hourPart) else { continue }
            guard let month = components.month, matchesCronField(month, pattern: monthPart) else { continue }

            let domMatches = domPart == "*" || matchesCronField(components.day ?? 0, pattern: domPart)
            let dowMatches = dowPart == "*" || matchesCronField(components.weekday ?? 0, pattern: dowPart)

            if (domPart == "*" && dowPart == "*") || (domMatches && dowMatches) || (domMatches && dowPart == "*") || (domPart == "*" && dowMatches) {
                var finalComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: current)
                finalComponents.second = 0
                return calendar.date(from: finalComponents)
            }
        }

        return nil
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
