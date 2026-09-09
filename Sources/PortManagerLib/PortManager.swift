import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - Port Process Model
public struct PortProcess: Codable, Identifiable, Sendable {
    // Identity fields (immutable — define equality and hashing)
    public let port: Int
    public let protocolName: String
    public let pid: Int
    public let user: String
    public let command: String

    // Enrichment fields (mutable — populated after initial discovery, excluded from hashing)
    public var fullCommand: String?
    public var parentPID: Int?
    public var startTime: Date?
    public var workingDirectory: String?
    public var processPath: String?
    public var socketPath: String?
    public var cpuUsage: Double?
    public var memoryMB: Double?
    /// True when the process is SIGSTOPped (ps STAT leading T/t). The socket
    /// stays bound — the process is frozen, not gone.
    public var isStopped: Bool = false

    // Framework detection fields
    public var framework: String?
    public var gitBranch: String?
    public var gitRepo: String?
    public var isOrphaned: Bool = false  // true if process is stale/zombie

    /// Unique ID: combines protocol+port for network, protocol+pid for sockets
    public var id: String {
        if protocolName == "unix" { return "unix-\(pid)" }
        return "\(protocolName)-\(port)-\(pid)"
    }

    /// Whether this is a Unix socket process (no network port)
    public var isUnixSocket: Bool { protocolName == "unix" }

    public init(port: Int, protocolName: String, pid: Int, user: String, command: String, fullCommand: String? = nil, parentPID: Int? = nil, startTime: Date? = nil, workingDirectory: String? = nil, processPath: String? = nil, socketPath: String? = nil, cpuUsage: Double? = nil, memoryMB: Double? = nil, framework: String? = nil, gitBranch: String? = nil, gitRepo: String? = nil, isOrphaned: Bool = false, isStopped: Bool = false) {
        self.port = port
        self.protocolName = protocolName
        self.pid = pid
        self.user = user
        self.command = command
        self.fullCommand = fullCommand
        self.parentPID = parentPID
        self.startTime = startTime
        self.workingDirectory = workingDirectory
        self.processPath = processPath
        self.socketPath = socketPath
        self.cpuUsage = cpuUsage
        self.memoryMB = memoryMB
        self.framework = framework
        self.gitBranch = gitBranch
        self.gitRepo = gitRepo
        self.isOrphaned = isOrphaned
        self.isStopped = isStopped
    }
}

// Hashable and Equatable based only on identity fields — enrichment fields are excluded
extension PortProcess: Hashable, Equatable {
    public static func == (lhs: PortProcess, rhs: PortProcess) -> Bool {
        lhs.port == rhs.port && lhs.protocolName == rhs.protocolName && lhs.pid == rhs.pid
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(port)
        hasher.combine(protocolName)
        hasher.combine(pid)
    }
}

// MARK: - Port Connection Model
public struct PortConnection: Codable, Hashable, Sendable {
    public let localAddress: String
    public let remoteAddress: String
    public let state: String
    public let pid: Int

    public init(localAddress: String, remoteAddress: String, state: String, pid: Int) {
        self.localAddress = localAddress
        self.remoteAddress = remoteAddress
        self.state = state
        self.pid = pid
    }
}

// MARK: - Established Connection Model
public struct EstablishedConnection: Codable, Identifiable, Sendable {
    public let id: String
    public let localAddress: String
    public let remoteAddress: String
    public let remoteHostname: String?
    public let state: String
    public let pid: Int
    public let processName: String
    public let user: String
    /// Whether this connection matches a blocklist entry in ~/.portpilot/blocklist.txt
    public var isBlocklisted: Bool = false

    public init(id: String = "", localAddress: String, remoteAddress: String, remoteHostname: String? = nil, state: String, pid: Int, processName: String, user: String, isBlocklisted: Bool = false) {
        if id.isEmpty {
            let uniqueString = "\(pid)-\(remoteAddress)-\(localAddress)-\(state)-\(processName)-\(user)"
            self.id = uniqueString
        } else {
            self.id = id
        }
        self.localAddress = localAddress
        self.remoteAddress = remoteAddress
        self.remoteHostname = remoteHostname
        self.state = state
        self.pid = pid
        self.processName = processName
        self.user = user
        self.isBlocklisted = isBlocklisted
    }
}

extension EstablishedConnection: Hashable {
    public static func == (lhs: EstablishedConnection, rhs: EstablishedConnection) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Port Category
public enum PortCategory: String, CaseIterable, Codable {
    case web
    case database
    case dev
    case system
    case custom

    public var defaultPorts: [Int] {
        switch self {
        case .web: return [80, 443, 8080, 8443, 3000, 3001, 5000, 5173, 4200, 9090]
        case .database: return [3306, 5432, 27017, 6379, 9200, 5984, 8529, 1433, 1521, 26257]
        case .dev: return [8000, 8888, 4000, 9000, 5500, 35729, 6006, 3100, 24678]
        case .system: return [22, 53, 67, 68, 123, 161, 162, 514, 631, 5353]
        case .custom: return []
        }
    }
}

// MARK: - Port Manager Error
public enum PortManagerError: LocalizedError {
    case noProcessFound(Int)
    case killFailed(Int, String)
    case partialKill([Int])
    case parseFailed(String)
    case invalidPID(Int)
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noProcessFound(let port):
            return "No process found listening on port \(port)"
        case .killFailed(let port, let reason):
            return "Failed to kill process on port \(port): \(reason)"
        case .partialKill(let pids):
            return "These processes did not exit: \(pids.map(String.init).joined(separator: ", "))"
        case .parseFailed(let reason):
            return "Failed to parse output: \(reason)"
        case .invalidPID(let pid):
            return "Invalid PID: \(pid). Must be a positive integer."
        case .launchFailed(let path):
            return "Failed to launch \(path)"
        }
    }
}

// MARK: - Cronjob Entry Model
public struct CronjobEntry: Codable, Identifiable, Sendable {
    public let id: String
    public let command: String
    public let schedule: String
    public let scheduleHuman: String?
    public let nextRun: Date?
    public let user: String?
    public let source: String
    public let isPaused: Bool

    public init(command: String, schedule: String, scheduleHuman: String? = nil, nextRun: Date? = nil, user: String? = nil, source: String, isPaused: Bool = false, duplicateIndex: Int? = nil) {
        // Stable across launches (unlike String.hashValue, which is randomized per process)
        // so run-history keyed by id still lines up after a restart. Schedule is part of
        // the key: the same command listed twice with different schedules is two jobs.
        // duplicateIndex disambiguates identical lines repeated in one crontab —
        // ForEach ids must stay unique.
        self.id = "\(source):\(schedule):\(command)" + (duplicateIndex.map { "#\($0)" } ?? "")
        self.command = command
        self.schedule = schedule
        self.scheduleHuman = scheduleHuman
        self.nextRun = nextRun
        self.user = user
        self.source = source
        self.isPaused = isPaused
    }

    /// Only entries that live in the user's own crontab can be paused/resumed in place.
    public var isEditable: Bool { source == "user" }
}

extension CronjobEntry: Hashable {
    public static func == (lhs: CronjobEntry, rhs: CronjobEntry) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Platform Detection
public enum Platform {
    case macOS
    case linux
    case windows
    case wsl // Windows Subsystem for Linux

    /// Cached — the Linux detection hits the filesystem, so this must not be
    /// recomputed on every call site.
    public static let current: Platform = detect()

    private static func detect() -> Platform {
        #if os(macOS)
        return .macOS
        #elseif os(Windows)
        return .windows
        #else
        if let version = try? String(contentsOfFile: "/proc/version", encoding: .utf8),
           version.lowercased().contains("microsoft") {
            return .wsl
        }
        if ProcessInfo.processInfo.environment["WSL_DISTRO_NAME"] != nil {
            return .wsl
        }
        return .linux
        #endif
    }

    public var isUnix: Bool {
        self == .macOS || self == .linux || self == .wsl
    }
}

// MARK: - Port Manager
public final class PortManager {

    public init() {}

    // Blocklist cache — accessed by PortManager+Connections.swift extension
    let blocklistLock = NSLock()
    var cachedBlocklist: Any? = nil
    var blocklistCacheTime: Date? = nil
    let blocklistCacheDuration: TimeInterval = 60

    var blocklistPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.portpilot/blocklist.txt"
    }

    // MARK: - Get PID for Port

    public func getPID(forPort port: Int, protocol: String = "tcp") -> Int? {
        let processes = (try? getListeningProcesses(startPort: port, endPort: port, protocolFilter: `protocol`, enrich: false)) ?? []
        return processes.first?.pid
    }

    public func getPIDs(forPorts ports: [Int], protocol: String = "tcp") -> [Int: Int] {
        var result: [Int: Int] = [:]
        for port in ports {
            if let pid = getPID(forPort: port, protocol: `protocol`) {
                result[port] = pid
            }
        }
        return result
    }

    // MARK: - Get Listening Processes

    public func getListeningProcesses(
        startPort: Int? = nil,
        endPort: Int? = nil,
        protocolFilter: String? = nil,
        enrich: Bool = true
    ) throws -> [PortProcess] {
        let platform = Platform.current
        let output: String

        switch platform {
        case .macOS:
            output = try runCommand("/usr/sbin/lsof", arguments: ["-iTCP", "-iUDP", "-sTCP:LISTEN", "-P", "-n"])
        case .linux, .wsl:
            // -tulnp: TCP and UDP listeners. ss lives in /usr/bin or /usr/sbin
            // depending on the distro's usr-merge state.
            output = try runCommand(Self.firstExisting(["/usr/bin/ss", "/usr/sbin/ss", "/bin/ss"]) ?? "/usr/bin/ss",
                                    arguments: ["-tulnp"])
        case .windows:
            output = try runCommand("netstat", arguments: ["-ano"])
        }

        var processes: [PortProcess] = []

        switch platform {
        case .macOS:
            processes = parseMacOSOutput(output)
        case .linux, .wsl:
            processes = parseLinuxOutput(output)
        case .windows:
            processes = try parseWindowsOutput(output)
        }

        var filtered = processes

        if let start = startPort {
            filtered = filtered.filter { $0.port >= start }
        }
        if let end = endPort {
            filtered = filtered.filter { $0.port <= end }
        }
        if let filter = protocolFilter {
            filtered = filtered.filter { $0.protocolName.lowercased() == filter.lowercased() }
        }

        let sorted = filtered.sorted { $0.port < $1.port }
        // Enrichment (2 ps spawns + proc_pidpath + framework/git file probes per
        // process) is real money — callers that only need pid presence skip it.
        return enrich ? fetchFullCommands(for: sorted) : sorted
    }

    // MARK: - Platform Parsers

    private func parseMacOSOutput(_ output: String) -> [PortProcess] {
        var processes: [PortProcess] = []
        var seen = Set<String>()

        for line in output.components(separatedBy: "\n").dropFirst() {
            guard !line.isEmpty else { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 9 else { continue }

            let command = parts[0]
            guard let pid = Int(parts[1]) else { continue }
            let user = parts[2]

            let nameField = parts[8]
            guard let colonIndex = nameField.lastIndex(of: ":") else { continue }
            let portString = String(nameField[nameField.index(after: colonIndex)...])
            guard let port = Int(portString) else { continue }

            // -sTCP:LISTEN filters TCP rows down to listeners; UDP rows pass
            // through unfiltered and never carry a state. So the (LISTEN)
            // marker on the NAME column is the reliable protocol discriminator
            // (a command name containing "TCP" is not).
            let proto = parts.count > 9 && parts[9] == "(LISTEN)" ? "tcp" : "udp"

            let key = "\(proto)-\(port)-\(pid)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            processes.append(PortProcess(
                port: port,
                protocolName: proto,
                pid: pid,
                user: user,
                command: command
            ))
        }

        return processes
    }

    private func parseLinuxOutput(_ output: String) -> [PortProcess] {
        var processes: [PortProcess] = []
        var seen = Set<String>()

        for line in output.components(separatedBy: "\n") {
            let columns = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard columns.count >= 5 else { continue }

            // `ss -tulnp` prepends a Netid column: State, Recv-Q, Send-Q shift
            // by one. TCP listeners report LISTEN; UDP reports UNCONN.
            let netid = columns[0].lowercased()
            let isTCP = netid.hasPrefix("tcp")
            let isUDP = netid.hasPrefix("udp")
            guard isTCP || isUDP else { continue }
            if isTCP && !line.contains("LISTEN") { continue }
            if isUDP && !line.contains("UNCONN") { continue }

            let localAddr = columns[4]
            guard let lastColon = localAddr.lastIndex(of: ":") else { continue }
            let portString = String(localAddr[localAddr.index(after: lastColon)...])
            guard let port = Int(portString) else { continue }

            let processInfo = columns.dropFirst(6).joined(separator: " ")
            var command = "unknown"
            var pid = 0

            if let cmdRange = processInfo.range(of: #"\(\"([^\"]+)\""#, options: .regularExpression) {
                command = String(processInfo[cmdRange])
                    .replacingOccurrences(of: "(\"", with: "")
                    .replacingOccurrences(of: "\"", with: "")
            }
            if let pidRange = processInfo.range(of: #"pid=(\d+)"#, options: .regularExpression) {
                let pidStr = String(processInfo[pidRange]).replacingOccurrences(of: "pid=", with: "")
                pid = Int(pidStr) ?? 0
            }

            var user = "unknown"
            if pid > 0,
               let uidLine = (try? String(contentsOfFile: "/proc/\(pid)/status", encoding: .utf8))?
                   .components(separatedBy: "\n")
                   .first(where: { $0.hasPrefix("Uid:") }) {
                let uidParts = uidLine.split(separator: "\t", omittingEmptySubsequences: true)
                if uidParts.count >= 2, let uid = Int(uidParts[1]) {
                    user = Self.userName(forUID: uid) ?? "unknown"
                }
            }

            let proto = isTCP ? "tcp" : "udp"
            let key = "\(proto)-\(port)-\(pid)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            processes.append(PortProcess(
                port: port,
                protocolName: proto,
                pid: pid,
                user: user,
                command: command
            ))
        }

        return processes
    }

    /// libc lookup — no subprocess, no per-call cache needed.
    private static func userName(forUID uid: Int) -> String? {
        guard let pw = getpwuid(uid_t(uid)), let name = pw.pointee.pw_name else { return nil }
        return String(cString: name)
    }

    private static func firstExisting(_ paths: [String]) -> String? {
        paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    private func parseWindowsOutput(_ output: String) throws -> [PortProcess] {
        var processes: [PortProcess] = []
        var seen = Set<Int>()

        var portToPID: [Int: Int] = [:]

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("TCP") || trimmed.hasPrefix("UDP") else { continue }
            guard trimmed.contains("LISTENING") else { continue }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 5 else { continue }

            let localAddr = parts[1]
            guard let colonIndex = localAddr.lastIndex(of: ":") else { continue }
            let portString = String(localAddr[localAddr.index(after: colonIndex)...])
            guard let port = Int(portString) else { continue }

            let pid = Int(parts[4]) ?? 0
            portToPID[port] = pid
        }

        let tasklistOutput = try runCommand("tasklist", arguments: ["/FO", "CSV", "/NH"])

        var pidToName: [Int: String] = [:]
        for line in tasklistOutput.components(separatedBy: "\n") {
            let parts = line.split(separator: ",").map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            guard parts.count >= 2 else { continue }
            if let pid = Int(parts[1]) {
                pidToName[pid] = parts[0]
            }
        }

        for (port, pid) in portToPID {
            guard !seen.contains(port) else { continue }
            seen.insert(port)

            let command = pidToName[pid] ?? "unknown"
            processes.append(PortProcess(
                port: port,
                protocolName: "tcp",
                pid: pid,
                user: "unknown",
                command: command
            ))
        }

        return processes
    }

    // MARK: - Fetch Full Commands

    private func fetchFullCommands(for processes: [PortProcess]) -> [PortProcess] {
        guard !processes.isEmpty else { return processes }

        let platform = Platform.current

        switch platform {
        case .macOS:
            return fetchFullCommandsMacOS(for: processes)
        case .linux, .wsl:
            return fetchFullCommandsLinux(for: processes)
        case .windows:
            return fetchFullCommandsWindows(for: processes)
        }
    }

    /// BSD ps `lstart` is "Mon Sep  8 01:02:03 2026" — the day-of-month may be
    /// space-padded, which makes naive whitespace splitting ambiguous. Capture
    /// the fields explicitly instead of counting tokens.
    private static let psLineNoUser = try! NSRegularExpression(
        pattern: #"^\s*(\d+)\s+(\d+)\s+([A-Za-z]{3})\s+([A-Za-z]{3})\s+(\d{1,2})\s+(\d{1,2}):(\d{2}):(\d{2})\s+(\d{4})(?:\s+(.*))?$"#
    )
    private static let psLineWithUser = try! NSRegularExpression(
        pattern: #"^\s*(\d+)\s+(\d+)\s+(\S+)\s+([A-Za-z]{3})\s+([A-Za-z]{3})\s+(\d{1,2})\s+(\d{1,2}):(\d{2}):(\d{2})\s+(\d{4})(?:\s+(.*))?$"#
    )

    private static let lstartFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter
    }()

    /// pid, ppid, start date, and args from a `ps -o pid=,ppid=,lstart=,args=` line.
    // internal for @testable — this parser carries the single-vs-double-digit-day fix
    static func parsePSLine(_ line: String, hasUser: Bool) -> (pid: Int, ppid: Int?, user: String?, startTime: Date?, args: String?)? {
        let regex = hasUser ? psLineWithUser : psLineNoUser
        guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }

        func group(_ idx: Int) -> String? {
            guard let range = Range(match.range(at: idx), in: line) else { return nil }
            return String(line[range])
        }

        guard let pidStr = group(1), let pid = Int(pidStr) else { return nil }
        let ppid = group(2).flatMap(Int.init)

        // Group layout differs between the two patterns — normalize indices.
        let dayOfWeek: String?, month: String?, day: String?, hh: String?, mm: String?, ss: String?, year: String?, args: String?
        let user: String?
        if hasUser {
            user = group(3)
            dayOfWeek = group(4); month = group(5); day = group(6)
            hh = group(7); mm = group(8); ss = group(9); year = group(10); args = group(11)
        } else {
            user = nil
            dayOfWeek = group(3); month = group(4); day = group(5)
            hh = group(6); mm = group(7); ss = group(8); year = group(9); args = group(10)
        }

        var startTime: Date?
        if let dayOfWeek, let month, let day, let hh, let mm, let ss, let year {
            startTime = lstartFormatter.date(from: "\(dayOfWeek) \(month) \(day) \(hh):\(mm):\(ss) \(year)")
        }

        return (pid, ppid, user, startTime, args)
    }

    /// macOS `ps` has no `cwd` keyword — asking for it makes ps exit 1 and emit
    /// a column-short output that misaligns positional parsers. Working
    /// directories come from lsof instead (one call for all pids).
    private func fetchWorkingDirectories(pids: String) -> [Int: String] {
        guard !pids.isEmpty else { return [:] }
        guard let output = try? runCommand("/usr/sbin/lsof",
                                           arguments: ["-w", "-a", "-p", pids, "-d", "cwd", "-F", "pn"],
                                           timeout: 5) else {
            return [:]
        }
        var result: [Int: String] = [:]
        var currentPID: Int?
        for record in output.split(separator: "\n") {
            guard let prefix = record.first, record.count > 1 else { continue }
            let value = String(record.dropFirst())
            switch prefix {
            case "p": currentPID = Int(value)
            case "n": if let pid = currentPID { result[pid] = value }
            default: break
            }
        }
        return result
    }

    private func fetchFullCommandsMacOS(for processes: [PortProcess]) -> [PortProcess] {
        let pids = processes.map { String($0.pid) }.joined(separator: ",")
        guard let output = try? runCommand("/bin/ps",
                                           arguments: ["-p", pids, "-o", "pid=,ppid=,lstart=,args="],
                                           environment: ["LC_ALL": "C"]) else {
            return processes
        }

        var pidToInfo: [Int: (args: String?, ppid: Int?, lstart: Date?)] = [:]
        for line in output.components(separatedBy: "\n") {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if let parsed = Self.parsePSLine(line, hasUser: false) {
                pidToInfo[parsed.pid] = (args: parsed.args, ppid: parsed.ppid, lstart: parsed.startTime)
            }
        }

        let cwdByPID = fetchWorkingDirectories(pids: pids)
        let stats = fetchProcessStats(pids: pids)

        var pidToPath: [Int: String] = [:]
        let classifier = ProcessClassifier.shared
        for process in processes {
            if let path = classifier.getProcessPath(pid: process.pid) {
                pidToPath[process.pid] = path
            }
        }

        return processes.map { process in
            var updated = process
            if let info = pidToInfo[process.pid] {
                updated.fullCommand = (info.args?.isEmpty == false) ? info.args : nil
                updated.parentPID = info.ppid
                updated.startTime = info.lstart
            }
            updated.workingDirectory = cwdByPID[process.pid]
            updated.cpuUsage = stats.cpu[process.pid]
            updated.memoryMB = stats.memMB[process.pid]
            updated.isStopped = stats.stopped[process.pid] ?? false
            updated.processPath = pidToPath[process.pid]
            updated.framework = detectFramework(for: updated.workingDirectory, processPath: updated.processPath)
            let gitInfo = detectGitInfo(for: updated.workingDirectory)
            updated.gitBranch = gitInfo.branch
            updated.gitRepo = gitInfo.repo
            return updated
        }
    }

    /// ps STAT codes: a leading `T` (or `t` on Linux) means the process is
    /// stopped — SIGSTOPped by job control or traced by a debugger. Both read
    /// as "paused" for our purposes.
    public static func isStoppedState(_ stat: String) -> Bool {
        stat.first == "T" || stat.first == "t"
    }

    private func fetchProcessStats(pids: String) -> (cpu: [Int: Double], memMB: [Int: Double], stopped: [Int: Bool]) {
        guard let output = try? runCommand("/bin/ps", arguments: ["-p", pids, "-o", "pid=,%cpu=,rss=,stat="]) else {
            return ([:], [:], [:])
        }
        var cpuMap: [Int: Double] = [:]
        var memMap: [Int: Double] = [:]
        var stoppedMap: [Int: Bool] = [:]
        for line in output.components(separatedBy: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces)
                .split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3,
                  let pid = Int(parts[0]),
                  let cpu = Double(parts[1]),
                  let rssKB = Double(parts[2]) else { continue }
            cpuMap[pid] = cpu
            memMap[pid] = rssKB / 1024.0
            if parts.count >= 4 {
                stoppedMap[pid] = Self.isStoppedState(String(parts[3]))
            }
        }
        return (cpuMap, memMap, stoppedMap)
    }

    private func fetchFullCommandsLinux(for processes: [PortProcess]) -> [PortProcess] {
        let pids = processes.map { String($0.pid) }.joined(separator: " ")
        guard !pids.isEmpty else { return processes }
        guard let output = try? runCommand("/bin/ps", arguments: ["-p", pids, "-o", "pid,args"]) else {
            return processes
        }

        var pidToArgs: [Int: String] = [:]
        for line in output.components(separatedBy: "\n").dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count >= 2, let pid = Int(parts[0]) else { continue }
            pidToArgs[pid] = String(parts[1...].joined(separator: " ").trimmingCharacters(in: .whitespaces))
        }

        let stats = fetchProcessStats(pids: pids)

        let classifier = ProcessClassifier.shared
        var pidToPath: [Int: String] = [:]
        var pidToCwd: [Int: String] = [:]
        for process in processes {
            if let path = classifier.getProcessPath(pid: process.pid) {
                pidToPath[process.pid] = path
            }
            if let cwd = try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/\(process.pid)/cwd") {
                pidToCwd[process.pid] = cwd
            }
        }

        return processes.map { process in
            var updated = process
            updated.fullCommand = pidToArgs[process.pid]
            updated.cpuUsage = stats.cpu[process.pid]
            updated.memoryMB = stats.memMB[process.pid]
            updated.isStopped = stats.stopped[process.pid] ?? false
            updated.processPath = pidToPath[process.pid]
            updated.workingDirectory = pidToCwd[process.pid]
            updated.framework = detectFramework(for: updated.workingDirectory, processPath: updated.processPath)
            let gitInfo = detectGitInfo(for: updated.workingDirectory)
            updated.gitBranch = gitInfo.branch
            updated.gitRepo = gitInfo.repo
            return updated
        }
    }

    private func fetchFullCommandsWindows(for processes: [PortProcess]) -> [PortProcess] {
        guard !processes.isEmpty else { return processes }

        var pidToCmd: [Int: String] = [:]
        for process in processes {
            guard let output = try? runCommand("wmic", arguments: ["process", "where", "ProcessId=\(process.pid)", "get", "CommandLine", "/format:csv"]) else {
                continue
            }

            let lines = output.components(separatedBy: "\n").filter { !$0.contains("Node") && !$0.isEmpty }
            if let lastLine = lines.last, !lastLine.contains("CommandLine") {
                let cmd = lastLine.trimmingCharacters(in: .whitespaces)
                if !cmd.isEmpty {
                    pidToCmd[process.pid] = cmd
                }
            }
        }

        return processes.map { process in
            var updated = process
            updated.fullCommand = pidToCmd[process.pid]
            updated.framework = detectFramework(for: updated.workingDirectory)
            let gitInfo = detectGitInfo(for: updated.workingDirectory)
            updated.gitBranch = gitInfo.branch
            updated.gitRepo = gitInfo.repo
            return updated
        }
    }

    // MARK: - Kill Process

    /// Sends TERM (or KILL when `force`), waits up to `timeout` seconds for the
    /// pids to exit, escalates stragglers to KILL. Returns pids still alive.
    @discardableResult
    public func killProcess(pids: [Int], force: Bool = false, timeout: TimeInterval = 5) -> [Int] {
        let valid = pids.filter { $0 > 1 }  // pid 1 = launchd/init; never signal it
        guard !valid.isEmpty else { return [] }

        func signalPID(_ pid: Int, _ sig: Int32) { kill(pid_t(pid), sig) }
        func isAlive(_ pid: Int) -> Bool { kill(pid_t(pid), 0) == 0 }

        let signal: Int32 = force ? SIGKILL : SIGTERM
        for pid in valid {
            signalPID(pid, signal)
        }

        guard !force else {
            usleep(150_000)
            return valid.filter(isAlive)
        }

        let deadline = Date().addingTimeInterval(timeout)
        var remaining = valid
        while Date() < deadline {
            usleep(100_000)
            remaining = remaining.filter(isAlive)
            if remaining.isEmpty { break }
        }

        for pid in remaining {
            signalPID(pid, SIGKILL)
        }
        if !remaining.isEmpty {
            usleep(150_000)
            return remaining.filter(isAlive)
        }
        return []
    }

    /// Kills every process listening on `port` (SO_REUSEPORT means there can be
    /// more than one), escalating TERM → KILL within `timeout` seconds.
    public func killProcessOnPort(_ port: Int, force: Bool = false, timeout: TimeInterval = 5) throws {
        let processes = try getListeningProcesses(startPort: port, endPort: port, enrich: false)
        guard !processes.isEmpty else {
            throw PortManagerError.noProcessFound(port)
        }
        let survivors = killProcess(pids: processes.map(\.pid), force: force, timeout: timeout)
        if !survivors.isEmpty {
            throw PortManagerError.partialKill(survivors)
        }
    }

    // MARK: - Pause / Resume Process

    /// Freezes processes with SIGSTOP. The kernel keeps their sockets bound —
    /// the port stays taken, the process just stops accepting. Returns the
    /// pids that were actually signaled.
    @discardableResult
    public func pauseProcess(pids: [Int]) -> [Int] {
        signalProcesses(pids, SIGSTOP)
    }

    /// Unfreezes SIGSTOPped processes with SIGCONT — state is intact, the
    /// listener picks up exactly where it froze.
    @discardableResult
    public func resumeProcess(pids: [Int]) -> [Int] {
        signalProcesses(pids, SIGCONT)
    }

    /// Pauses every process listening on `port` (SO_REUSEPORT allows more
    /// than one). A frozen process still owns its socket, so discovery keeps
    /// finding it.
    @discardableResult
    public func pauseProcessOnPort(_ port: Int) throws -> [Int] {
        let processes = try getListeningProcesses(startPort: port, endPort: port, enrich: false)
        guard !processes.isEmpty else {
            throw PortManagerError.noProcessFound(port)
        }
        return pauseProcess(pids: processes.map(\.pid))
    }

    /// Resumes every process listening on `port`.
    @discardableResult
    public func resumeProcessOnPort(_ port: Int) throws -> [Int] {
        let processes = try getListeningProcesses(startPort: port, endPort: port, enrich: false)
        guard !processes.isEmpty else {
            throw PortManagerError.noProcessFound(port)
        }
        return resumeProcess(pids: processes.map(\.pid))
    }

    /// Deliver `sig` to each pid we're allowed to signal. pid 1 is excluded
    /// (launchd/init — same guard as killProcess) and pids we don't own come
    /// back as failures from kill(2), which the filter drops.
    private func signalProcesses(_ pids: [Int], _ sig: Int32) -> [Int] {
        pids.filter { $0 > 1 }.filter { kill(pid_t($0), sig) == 0 }
    }

    public func killAllProcesses(startPort: Int? = nil, endPort: Int? = nil, force: Bool = false, pattern: String? = nil) throws {
        var processes = try getListeningProcesses(startPort: startPort, endPort: endPort, enrich: false)

        if let pattern = pattern, !pattern.isEmpty {
            let lowercasedPattern = pattern.lowercased()
            processes = processes.filter { $0.command.lowercased().contains(lowercasedPattern) }
        }
        guard !processes.isEmpty else { return }

        // One discovery pass, direct PID kills — not killProcessOnPort per row,
        // which used to re-run the whole lsof+ps pipeline for each process.
        let survivors = killProcess(pids: processes.map(\.pid), force: force)
        if !survivors.isEmpty {
            throw PortManagerError.partialKill(survivors)
        }
    }

    // MARK: - Find Available Ports

    public func findAvailablePorts(startPort: Int? = nil, endPort: Int? = nil, count: Int = 1) throws -> [Int] {
        let start = startPort ?? 1024
        let end = endPort ?? 65535
        guard start <= end else { return [] }
        var availablePorts: [Int] = []

        let occupiedPorts = Set((try getListeningProcesses(enrich: false)).map { $0.port })

        for port in start...end {
            guard availablePorts.count < count else { break }

            if occupiedPorts.contains(port) {
                continue
            }

            if isPortAvailable(port) {
                availablePorts.append(port)
            }
        }

        return availablePorts
    }

    public func isPortAvailable(_ port: Int) -> Bool {
        let platform = Platform.current

        switch platform {
        case .macOS, .linux, .wsl:
            return checkPortAvailabilityMacOS(port)
        case .windows:
            return checkPortAvailabilityWindows(port)
        }
    }

    private func checkPortAvailabilityMacOS(_ port: Int) -> Bool {
        let output = runCommandQuiet("/usr/sbin/lsof", arguments: ["-iTCP:\(port)", "-sTCP:LISTEN", "-P", "-n"])
        return output.isEmpty
    }

    private func checkPortAvailabilityWindows(_ port: Int) -> Bool {
        let output = runCommandQuiet("netstat", arguments: ["-ano"])
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("LISTENING") && trimmed.contains(":\(port)") {
                return false
            }
        }
        return true
    }

    // MARK: - Categorize Port

    public func categorizePort(_ port: Int) -> PortCategory? {
        for category in PortCategory.allCases {
            if category.defaultPorts.contains(port) {
                return category
            }
        }
        return nil
    }

    // MARK: - Get Parent Process Name

    public func getParentProcessName(forPID pid: Int) -> String? {
        getParentProcessNames(forPIDs: [pid])[pid]
    }

    public func getParentProcessNames(forPIDs pids: [Int]) -> [Int: String] {
        let uniquePIDs = Array(Set(pids)).sorted()
        guard !uniquePIDs.isEmpty else { return [:] }

        let pidList = uniquePIDs.map(String.init).joined(separator: ",")
        guard let output = try? runCommand("/bin/ps", arguments: ["-p", pidList, "-o", "pid=,comm="]) else {
            return [:]
        }

        var namesByPID: [Int: String] = [:]
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let pid = Int(parts[0]) else { continue }

            let name = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            namesByPID[pid] = name
        }

        return namesByPID
    }

    // MARK: - Get Processes by Name

    public func getProcessesByName(names: [String]) -> [PortProcess] {
        let platform = Platform.current

        switch platform {
        case .macOS:
            return getProcessesByNameMacOS(names: names)
        case .linux, .wsl:
            return getProcessesByNameLinux(names: names)
        case .windows:
            return getProcessesByNameWindows(names: names)
        }
    }

    private func getProcessesByNameMacOS(names: [String]) -> [PortProcess] {
        var allProcesses: [PortProcess] = []

        for name in names {
            guard let output = try? runCommand("/usr/bin/pgrep", arguments: ["-f", name]) else {
                continue
            }

            let pids = output.split(separator: "\n").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }

            for pid in pids {
                if let process = getMacOSProcessInfo(pid: pid, name: name) {
                    allProcesses.append(process)
                }
            }
        }

        if allProcesses.isEmpty {
            guard let psOutput = try? runCommand("/bin/ps", arguments: ["-ax", "-o", "pid=,ppid=,user=,command="]) else {
                return []
            }

            for line in psOutput.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = String(line).trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }

                let parts = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true).map(String.init)
                guard parts.count >= 4 else { continue }

                guard let pid = Int(parts[0]) else { continue }
                let ppid = Int(parts[1])
                let user = parts[2]
                let command = parts[3]

                let commandLower = command.lowercased()
                for name in names {
                    if commandLower.contains(name.lowercased()) {
                        if allProcesses.contains(where: { $0.pid == pid }) {
                            continue
                        }
                        let portProcess = PortProcess(
                            port: 0,
                            protocolName: "process",
                            pid: pid,
                            user: user,
                            command: command.split(separator: "/").last.map(String.init) ?? command,
                            fullCommand: command,
                            parentPID: ppid
                        )
                        allProcesses.append(portProcess)
                        break
                    }
                }
            }
        }

        return allProcesses
    }

    private func getMacOSProcessInfo(pid: Int, name: String) -> PortProcess? {
        guard let output = try? runCommand("/bin/ps",
                                           arguments: ["-p", String(pid), "-o", "pid=,ppid=,user=,lstart=,args="],
                                           environment: ["LC_ALL": "C"]) else {
            return nil
        }

        for line in output.components(separatedBy: "\n") {
            guard let parsed = Self.parsePSLine(line, hasUser: true), parsed.pid == pid else { continue }
            return PortProcess(
                port: 0,
                protocolName: "process",
                pid: pid,
                user: parsed.user ?? "unknown",
                command: parsed.args?.split(separator: "/").last.map(String.init) ?? name,
                fullCommand: parsed.args,
                parentPID: parsed.ppid,
                startTime: parsed.startTime,
                workingDirectory: fetchWorkingDirectories(pids: String(pid))[pid]
            )
        }

        return nil
    }

    private func getProcessesByNameLinux(names: [String]) -> [PortProcess] {
        var allProcesses: [PortProcess] = []

        for name in names {
            guard let output = try? runCommand("/usr/bin/pgrep", arguments: ["-f", name]) else {
                continue
            }

            let pids = output.split(separator: "\n").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }

            for pid in pids {
                if let process = getLinuxProcessInfo(pid: pid, name: name) {
                    allProcesses.append(process)
                }
            }
        }

        return allProcesses
    }

    private func getLinuxProcessInfo(pid: Int, name: String) -> PortProcess? {
        guard let output = try? runCommand("/bin/ps", arguments: ["-p", String(pid), "-o", "pid,ppid,user,args"]) else {
            return nil
        }

        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 2 else { return nil }

        let parts = lines[1].trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 4 else { return nil }

        return PortProcess(
            port: 0,
            protocolName: "process",
            pid: pid,
            user: parts[2],
            command: parts[3].split(separator: "/").last.map(String.init) ?? name,
            fullCommand: parts[3],
            parentPID: Int(parts[1])
        )
    }

    private func getProcessesByNameWindows(names: [String]) -> [PortProcess] {
        var allProcesses: [PortProcess] = []

        guard let tasklistOutput = try? runCommand("tasklist", arguments: ["/FO", "CSV", "/NH"]) else {
            return []
        }

        var pidToName: [Int: String] = [:]
        for line in tasklistOutput.split(separator: "\n", omittingEmptySubsequences: false) {
            let parts = String(line).split(separator: ",").map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            guard parts.count >= 2 else { continue }
            if let pid = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                pidToName[pid] = parts[0]
            }
        }

        for (pid, processName) in pidToName {
            let processNameLower = processName.lowercased()
            for name in names {
                if processNameLower.contains(name.lowercased()) {
                    let portProcess = PortProcess(
                        port: 0,
                        protocolName: "process",
                        pid: pid,
                        user: "unknown",
                        command: processName,
                        fullCommand: processName
                    )
                    allProcesses.append(portProcess)
                    break
                }
            }
        }

        return allProcesses
    }

    // MARK: - Kill Process by Name

    public func killAllProcesses(named names: [String], force: Bool = false) throws {
        let processes = getProcessesByName(names: names)
        for process in processes {
            let signal = force ? "KILL" : "TERM"
            _ = try runCommand("/bin/kill", arguments: ["-s", signal, "\(process.pid)"])
        }
    }

    public func killProcessByPID(_ pid: Int, force: Bool = false, timeout: TimeInterval = 5) throws {
        guard pid > 0 else {
            throw PortManagerError.invalidPID(pid)
        }
        let survivors = killProcess(pids: [pid], force: force, timeout: timeout)
        if !survivors.isEmpty {
            throw PortManagerError.partialKill(survivors)
        }
    }

    // MARK: - Unix Socket Discovery

    public func getUnixSocketProcesses() -> [PortProcess] {
        guard Platform.current == .macOS else { return [] }

        guard let output = try? runCommand("/usr/sbin/lsof", arguments: ["-U", "-P", "-n"]) else {
            return []
        }

        var processes: [PortProcess] = []
        var seenPIDs = Set<Int>()

        for line in output.components(separatedBy: "\n").dropFirst() {
            guard !line.isEmpty else { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 8 else { continue }

            let command = parts[0]
            guard let pid = Int(parts[1]) else { continue }
            let user = parts[2]

            let nameField = parts.count > 8
                ? parts[8...].joined(separator: " ")
                : (parts.last ?? "")

            guard nameField.contains("/") else { continue }

            if seenPIDs.contains(pid) { continue }
            seenPIDs.insert(pid)

            processes.append(PortProcess(
                port: 0,
                protocolName: "unix",
                pid: pid,
                user: user,
                command: command,
                socketPath: nameField
            ))
        }

        return fetchFullCommands(for: processes)
    }

    // MARK: - Shell Command Runner

    struct CommandOutput {
        let output: String
        /// nil when the process was killed by the timeout or failed to launch.
        let exitStatus: Int32?
        let timedOut: Bool
    }

    /// Core runner. Drains stdout concurrently — a child writing more than the
    /// pipe capacity would otherwise block on write and never exit — enforces
    /// `timeout` for real (TERM first, KILL after a 2 s grace), and reports the
    /// exit status so callers can stop parsing error text as data.
    func runProcess(_ path: String, arguments: [String], timeout: TimeInterval = 10,
                    environment extraEnv: [String: String]? = nil) -> CommandOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        if let extraEnv {
            var env = ProcessInfo.processInfo.environment
            for (key, value) in extraEnv { env[key] = value }
            process.environment = env
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            // Launch failure (missing binary, exec format error): return, never
            // touch termination APIs on an unlaunched Process.
            return CommandOutput(output: "", exitStatus: nil, timedOut: false)
        }

        let drainLock = NSLock()
        var collected = Data()
        let drained = DispatchSemaphore(value: 0)
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

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 2)
            }
            // A grandchild holding the pipe open can delay EOF past the kill;
            // take what we have rather than block forever.
        }
        _ = drained.wait(timeout: .now() + 1)

        drainLock.lock()
        let output = String(data: collected, encoding: .utf8) ?? ""
        drainLock.unlock()

        let status: Int32? = timedOut ? nil : process.terminationStatus
        return CommandOutput(output: output, exitStatus: status, timedOut: timedOut)
    }

    func runCommand(_ path: String, arguments: [String], timeout: TimeInterval = 10,
                    environment: [String: String]? = nil) throws -> String {
        let result = runProcess(path, arguments: arguments, timeout: timeout, environment: environment)
        if result.exitStatus == nil && !result.timedOut {
            throw PortManagerError.launchFailed(path)
        }
        return result.output
    }

    func runCommandQuiet(_ path: String, arguments: [String], timeout: TimeInterval = 10) -> String {
        runProcess(path, arguments: arguments, timeout: timeout).output
    }
}
