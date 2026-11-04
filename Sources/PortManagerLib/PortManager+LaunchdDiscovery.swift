import Foundation

// MARK: - launchd Schedule Discovery

/// Whether launchd currently has a job loaded in the user's GUI domain.
/// `unknown` means the check itself failed; it never stands in for "not loaded".
public enum LaunchdLoadState: String, Codable, Sendable {
    case loaded
    case notLoaded
    case unknown
}

/// A scheduled job from the user's LaunchAgents folder. Read-only by design: it is a separate
/// type from `CronjobEntry`, so it can't reach the cron edit, Run Now or Stop paths.
/// It has no field for `EnvironmentVariables`, which often hold secrets.
public struct LaunchdJobEntry: Codable, Identifiable, Sendable, Hashable {
    public var id: String { label }
    public let label: String
    public let command: String
    public let scheduleHuman: String
    /// nil for interval jobs: launchd doesn't report when an interval next fires.
    public let nextRun: Date?
    public let plistPath: String
    public let logPath: String?
    public let loadState: LaunchdLoadState
    public let isRunning: Bool?
    public let lastExitCode: Int?
    public let runCount: Int?
}

public struct LaunchdDiscoverySnapshot: Sendable {
    public let entries: [LaunchdJobEntry]
    public let errors: [String]
    /// Agents with no StartCalendarInterval or StartInterval, such as always-on daemons.
    public let unscheduledCount: Int

    public init(entries: [LaunchdJobEntry] = [], errors: [String] = [], unscheduledCount: Int = 0) {
        self.entries = entries
        self.errors = errors
        self.unscheduledCount = unscheduledCount
    }

    public var isComplete: Bool { errors.isEmpty }
    public var errorDescription: String { errors.joined(separator: "; ") }
}

/// Pure parsing, with no file or process access, so it can run on synthetic plists.
enum LaunchdPlist {
    struct Parsed: Equatable {
        let label: String
        let command: String
        let scheduleHuman: String
        let nextRun: Date?
        let logPath: String?
    }

    enum ParseError: Error, Equatable {
        case notAPlist
        case noLabel
        case badSchedule(String)
    }

    /// Returns nil for a valid agent that has no schedule.
    static func parse(_ data: Data, now: Date, calendar: Calendar = .current) throws -> Parsed? {
        let raw = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let plist = raw as? [String: Any] else { throw ParseError.notAPlist }
        // No schedule means no job to list. Real agents folders hold empty plists too.
        guard plist["StartCalendarInterval"] != nil || plist["StartInterval"] != nil else { return nil }
        guard let label = plist["Label"] as? String, !label.isEmpty else { throw ParseError.noLabel }

        let human: String
        var next: Date?
        if let value = plist["StartCalendarInterval"] {
            let intervals: [[String: Int]]
            if let one = value as? [String: Int] {
                intervals = [one]
            } else if let many = value as? [[String: Int]], !many.isEmpty {
                intervals = many
            } else {
                throw ParseError.badSchedule("StartCalendarInterval")
            }
            for interval in intervals {
                guard isValid(interval) else { throw ParseError.badSchedule("StartCalendarInterval") }
            }
            human = intervals.count == 1 ? describe(intervals[0]) : "\(intervals.count) calendar times"
            next = intervals.compactMap { nextFire(of: $0, after: now, calendar: calendar) }.min()
        } else if let value = plist["StartInterval"] {
            guard let seconds = value as? Int, seconds > 0 else { throw ParseError.badSchedule("StartInterval") }
            human = describe(seconds: seconds)
        } else {
            return nil
        }

        let arguments = plist["ProgramArguments"] as? [String]
        let command = arguments?.joined(separator: " ") ?? (plist["Program"] as? String) ?? "(no program)"
        let logPath = (plist["StandardOutPath"] as? String) ?? (plist["StandardErrorPath"] as? String)
        return Parsed(label: label, command: command, scheduleHuman: human, nextRun: next, logPath: logPath)
    }

    private static let ranges: [String: ClosedRange<Int>] = [
        "Minute": 0...59, "Hour": 0...23, "Day": 1...31, "Weekday": 0...7, "Month": 1...12,
    ]

    private static func isValid(_ interval: [String: Int]) -> Bool {
        interval.allSatisfy { key, value in ranges[key]?.contains(value) == true }
    }

    /// launchd counts Sunday as 0 or 7; Foundation counts it as 1.
    private static func foundationWeekday(_ launchd: Int) -> Int { launchd % 7 + 1 }

    /// Fields left out are wildcards. With both Day and Weekday set, either match fires, as in cron.
    static func nextFire(of interval: [String: Int], after now: Date, calendar: Calendar) -> Date? {
        func next(day: Int?, weekday: Int?) -> Date? {
            var parts = DateComponents()
            parts.month = interval["Month"]
            parts.day = day
            parts.weekday = weekday
            parts.hour = interval["Hour"]
            parts.minute = interval["Minute"]
            parts.second = 0
            return calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTime)
        }
        let weekday = interval["Weekday"].map(foundationWeekday)
        if let day = interval["Day"], let weekday {
            return [next(day: day, weekday: nil), next(day: nil, weekday: weekday)].compactMap { $0 }.min()
        }
        return next(day: interval["Day"], weekday: weekday)
    }

    private static let weekdayNames = ["Sundays", "Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays"]

    static func describe(_ interval: [String: Int]) -> String {
        let hour = interval["Hour"]
        let minute = interval["Minute"]
        let time: String
        switch (hour, minute) {
        case let (h?, m?): time = String(format: "%02d:%02d", h, m)
        case let (h?, nil): time = String(format: "every minute of %02d:xx", h)
        default: time = ""
        }
        if let month = interval["Month"] {
            let day = interval["Day"].map { " day \($0)" } ?? ""
            return "Month \(month)\(day)\(time.isEmpty ? "" : " at \(time)")"
        }
        if let day = interval["Day"] {
            return "Monthly on day \(day)\(time.isEmpty ? "" : " at \(time)")"
        }
        if let weekday = interval["Weekday"] {
            return "\(weekdayNames[weekday % 7])\(time.isEmpty ? "" : " at \(time)")"
        }
        if !time.isEmpty { return hour != nil && minute != nil ? "Daily at \(time)" : "Daily, \(time)" }
        if let minute { return String(format: "Hourly at :%02d", minute) }
        return "Every minute"
    }

    static func describe(seconds: Int) -> String {
        func unit(_ value: Int, _ name: String) -> String { value == 1 ? "Every \(name)" : "Every \(value) \(name)s" }
        if seconds % 604_800 == 0 { return unit(seconds / 604_800, "week") }
        if seconds % 86_400 == 0 { return unit(seconds / 86_400, "day") }
        if seconds % 3_600 == 0 { return unit(seconds / 3_600, "hour") }
        if seconds % 60 == 0 { return unit(seconds / 60, "minute") }
        return unit(seconds, "second")
    }

    struct RuntimeState: Equatable {
        let isRunning: Bool?
        let lastExitCode: Int?
        let runCount: Int?
    }

    /// Reads only the job's own lines, which have one leading tab; nested blocks repeat these keys.
    static func parseRuntimeState(_ output: String) -> RuntimeState {
        func value(_ key: String) -> String? {
            let prefix = "\t\(key) = "
            return output.split(separator: "\n", omittingEmptySubsequences: true)
                .first { $0.hasPrefix(prefix) }
                .map { String($0.dropFirst(prefix.count)) }
        }
        return RuntimeState(
            isRunning: value("state").map { $0 == "running" },
            lastExitCode: value("last exit code").flatMap { Int($0) },
            runCount: value("runs").flatMap { Int($0) }
        )
    }
}

extension PortManager {
    private static let launchdMaxFiles = 512
    private static let launchdMaxPlistBytes = 1 << 20

    /// Read the user's scheduled launch agents. A file or check that fails is reported in
    /// `errors`, never treated as an empty result. Nothing here changes launchd state.
    public func getLaunchdSnapshot(
        directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents"),
        now: Date = Date()
    ) -> LaunchdDiscoverySnapshot {
        guard Platform.current == .macOS else { return LaunchdDiscoverySnapshot() }

        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch CocoaError.fileReadNoSuchFile {
            return LaunchdDiscoverySnapshot()
        } catch {
            return LaunchdDiscoverySnapshot(errors: ["Could not read \(directory.path): \(error.localizedDescription)"])
        }

        var plists = names.filter { $0.hasSuffix(".plist") }.sorted()
        var errors: [String] = []
        if plists.count > Self.launchdMaxFiles {
            errors.append("Only the first \(Self.launchdMaxFiles) of \(plists.count) launch agents were read")
            plists = Array(plists.prefix(Self.launchdMaxFiles))
        }

        var entries: [LaunchdJobEntry] = []
        var unscheduled = 0
        for name in plists {
            let url = directory.appendingPathComponent(name)
            do {
                guard let parsed = try LaunchdPlist.parse(Self.readLaunchdPlist(url), now: now) else {
                    unscheduled += 1
                    continue
                }
                let runtime = launchdRuntime(label: parsed.label)
                if case .failure(let message) = runtime {
                    errors.append("\(parsed.label): \(message)")
                }
                let state = runtime.state
                entries.append(LaunchdJobEntry(
                    label: parsed.label,
                    command: parsed.command,
                    scheduleHuman: parsed.scheduleHuman,
                    nextRun: parsed.nextRun,
                    plistPath: url.path,
                    logPath: parsed.logPath,
                    loadState: runtime.loadState,
                    isRunning: state?.isRunning,
                    lastExitCode: state?.lastExitCode,
                    runCount: state?.runCount
                ))
            } catch {
                errors.append("\(name): \(Self.describeLaunchdError(error))")
            }
        }
        entries.sort { ($0.nextRun ?? .distantFuture, $0.label) < ($1.nextRun ?? .distantFuture, $1.label) }
        return LaunchdDiscoverySnapshot(entries: entries, errors: errors, unscheduledCount: unscheduled)
    }

    private static func readLaunchdPlist(_ url: URL) throws -> Data {
        let values = try url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "not a regular file"])
        }
        guard (values.fileSize ?? 0) <= launchdMaxPlistBytes else {
            throw CocoaError(.fileReadTooLarge, userInfo: [NSLocalizedDescriptionKey: "larger than 1 MiB"])
        }
        return try Data(contentsOf: url)
    }

    private static func describeLaunchdError(_ error: Error) -> String {
        switch error {
        case LaunchdPlist.ParseError.notAPlist: return "not a readable property list"
        case LaunchdPlist.ParseError.noLabel: return "has no Label"
        case LaunchdPlist.ParseError.badSchedule(let key): return "invalid \(key)"
        default: return error.localizedDescription
        }
    }

    private enum LaunchdRuntime {
        case loaded(LaunchdPlist.RuntimeState)
        case notLoaded
        case failure(String)

        var loadState: LaunchdLoadState {
            switch self {
            case .loaded: return .loaded
            case .notLoaded: return .notLoaded
            case .failure: return .unknown
            }
        }

        var state: LaunchdPlist.RuntimeState? {
            if case .loaded(let state) = self { return state }
            return nil
        }
    }

    private func launchdRuntime(label: String) -> LaunchdRuntime {
        let result = runProcess(
            "/bin/launchctl",
            arguments: ["print", "gui/\(getuid())/\(label)"],
            timeout: 5,
            environment: ["LC_ALL": "C"]
        )
        if result.timedOut { return .failure("launchctl print timed out") }
        if result.outputTruncated { return .failure("launchctl print output was truncated") }
        guard let status = result.exitStatus else { return .failure("launchctl could not be launched") }
        if status == 0 { return .loaded(LaunchdPlist.parseRuntimeState(result.output)) }
        // 113 is launchd's "could not find service".
        if status == 113 { return .notLoaded }
        return .failure("launchctl print exited with status \(status)")
    }
}
