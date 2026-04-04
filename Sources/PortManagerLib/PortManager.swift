import Foundation

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

    public init(port: Int, protocolName: String, pid: Int, user: String, command: String, fullCommand: String? = nil, parentPID: Int? = nil, startTime: Date? = nil, workingDirectory: String? = nil, processPath: String? = nil, socketPath: String? = nil, cpuUsage: Double? = nil, memoryMB: Double? = nil, framework: String? = nil, gitBranch: String? = nil, gitRepo: String? = nil, isOrphaned: Bool = false) {
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
    case parseFailed(String)
    case invalidPID(Int)

    public var errorDescription: String? {
        switch self {
        case .noProcessFound(let port):
            return "No process found listening on port \(port)"
        case .killFailed(let port, let reason):
            return "Failed to kill process on port \(port): \(reason)"
        case .parseFailed(let reason):
            return "Failed to parse output: \(reason)"
        case .invalidPID(let pid):
            return "Invalid PID: \(pid). Must be a positive integer."
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

    public init(command: String, schedule: String, scheduleHuman: String? = nil, nextRun: Date? = nil, user: String? = nil, source: String) {
        self.id = "\(source):\(command)".hashValue.description
        self.command = command
        self.schedule = schedule
        self.scheduleHuman = scheduleHuman
        self.nextRun = nextRun
        self.user = user
        self.source = source
    }
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

    public static var current: Platform {
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
    var cachedBlocklist: Any? = nil
    var blocklistCacheTime: Date? = nil
    let blocklistCacheDuration: TimeInterval = 60

    var blocklistPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.portpilot/blocklist.txt"
    }

    // MARK: - Get PID for Port

    public func getPID(forPort port: Int, protocol: String = "tcp") -> Int? {
        let processes = (try? getListeningProcesses(startPort: port, endPort: port, protocolFilter: `protocol`)) ?? []
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
        protocolFilter: String? = nil
    ) throws -> [PortProcess] {
        let platform = Platform.current
        let output: String

        switch platform {
        case .macOS:
            output = try runCommand("/usr/sbin/lsof", arguments: ["-iTCP", "-iUDP", "-sTCP:LISTEN", "-P", "-n"])
        case .linux, .wsl:
            output = try runCommand("/usr/bin/ss", arguments: ["-tlnp"])
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
        return fetchFullCommands(for: sorted)
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

            let proto = line.contains("TCP") ? "tcp" : "udp"

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
            guard line.contains("LISTEN") else { continue }

            let columns = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard columns.count >= 5 else { continue }

            let localAddr = columns[3]
            guard let lastColon = localAddr.lastIndex(of: ":") else { continue }
            let portString = String(localAddr[localAddr.index(after: lastColon)...])
            guard let port = Int(portString) else { continue }

            let processInfo = columns.dropFirst(5).joined(separator: " ")
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
            if pid > 0 {
                if let statusOutput = try? runCommand("/bin/cat", arguments: ["/proc/\(pid)/status"]),
                   let uidLine = statusOutput.components(separatedBy: "\n").first(where: { $0.hasPrefix("Uid:") }) {
                    let uidParts = uidLine.split(separator: "\t", omittingEmptySubsequences: true)
                    if uidParts.count >= 2, let uid = Int(uidParts[1]) {
                        if let passwdLine = try? runCommand("/usr/bin/id", arguments: ["-nu", String(uid)]) {
                            user = passwdLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }
            }

            let key = "tcp-\(port)-\(pid)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            processes.append(PortProcess(
                port: port,
                protocolName: "tcp",
                pid: pid,
                user: user,
                command: command
            ))
        }

        return processes
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

    private func fetchFullCommandsMacOS(for processes: [PortProcess]) -> [PortProcess] {
        let pids = processes.map { String($0.pid) }.joined(separator: ",")
        guard let output = try? runCommand("/bin/ps", arguments: ["-p", pids, "-o", "pid=,ppid=,lstart=,cwd=,args="]) else {
            return processes
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"

        var pidToInfo: [Int: (args: String, ppid: Int?, lstart: Date?, cwd: String?)] = [:]
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            guard let firstSpaceIdx = trimmed.firstIndex(of: " ") else { continue }
            let pidStr = String(trimmed[..<firstSpaceIdx])
            guard let pid = Int(pidStr) else { continue }

            let rest = String(trimmed[trimmed.index(after: firstSpaceIdx)...])

            let tokens = rest.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            var ppid: Int?
            var lstart: Date?
            var cwd: String?
            var args: String?

            if tokens.count >= 1 {
                ppid = Int(tokens[0])
            }

            if tokens.count >= 6 {
                let lstartStr = tokens[1...5].joined(separator: " ")
                lstart = dateFormatter.date(from: lstartStr)
            }
            if tokens.count >= 7 {
                cwd = tokens[6]
                args = tokens.dropFirst(7).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            }

            pidToInfo[pid] = (args: args ?? "", ppid: ppid, lstart: lstart, cwd: cwd)
        }

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
                updated.fullCommand = info.args.isEmpty ? nil : info.args
                updated.parentPID = info.ppid
                updated.startTime = info.lstart
                updated.workingDirectory = info.cwd
            }
            updated.cpuUsage = stats.cpu[process.pid]
            updated.memoryMB = stats.memMB[process.pid]
            updated.processPath = pidToPath[process.pid]
            updated.framework = detectFramework(for: updated.workingDirectory, processPath: updated.processPath)
            let gitInfo = detectGitInfo(for: updated.workingDirectory)
            updated.gitBranch = gitInfo.branch
            updated.gitRepo = gitInfo.repo
            return updated
        }
    }

    private func fetchProcessStats(pids: String) -> (cpu: [Int: Double], memMB: [Int: Double]) {
        guard let output = try? runCommand("/bin/ps", arguments: ["-p", pids, "-o", "pid=,%cpu=,rss="]) else {
            return ([:], [:])
        }
        var cpuMap: [Int: Double] = [:]
        var memMap: [Int: Double] = [:]
        for line in output.components(separatedBy: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces)
                .split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3,
                  let pid = Int(parts[0]),
                  let cpu = Double(parts[1]),
                  let rssKB = Double(parts[2]) else { continue }
            cpuMap[pid] = cpu
            memMap[pid] = rssKB / 1024.0
        }
        return (cpuMap, memMap)
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

    public func killProcessOnPort(_ port: Int, force: Bool = false, timeout: Int = 5000) throws {
        let processes = try getListeningProcesses(startPort: port, endPort: port)
        guard let process = processes.first else {
            throw PortManagerError.noProcessFound(port)
        }

        let signal = force ? "KILL" : "TERM"
        let result = try runCommand("/bin/kill", arguments: ["-s", signal, "\(process.pid)"])
        _ = result
    }

    public func killAllProcesses(startPort: Int? = nil, endPort: Int? = nil, force: Bool = false) throws {
        let processes = try getListeningProcesses(startPort: startPort, endPort: endPort)
        for process in processes {
            try killProcessOnPort(process.port, force: force)
        }
    }

    public func killAllProcesses(startPort: Int? = nil, endPort: Int? = nil, force: Bool = false, pattern: String?) throws {
        var processes = try getListeningProcesses(startPort: startPort, endPort: endPort)

        if let pattern = pattern, !pattern.isEmpty {
            let lowercasedPattern = pattern.lowercased()
            processes = processes.filter { $0.command.lowercased().contains(lowercasedPattern) }
        }

        for process in processes {
            try killProcessOnPort(process.port, force: force)
        }
    }

    // MARK: - Find Available Ports

    public func findAvailablePorts(startPort: Int? = nil, endPort: Int? = nil, count: Int = 1) throws -> [Int] {
        let start = startPort ?? 1024
        let end = endPort ?? 65535
        var availablePorts: [Int] = []

        let occupiedPorts = Set((try getListeningProcesses()).map { $0.port })

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
        guard let output = try? runCommand("/bin/ps", arguments: ["-p", String(pid), "-o", "pid=,ppid=,user=,lstart=,cwd=,args="]) else {
            return nil
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"

        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            guard let firstSpaceIdx = trimmed.firstIndex(of: " ") else { continue }
            let pidStr = String(trimmed[..<firstSpaceIdx])
            guard let pidVal = Int(pidStr), pidVal == pid else { continue }

            let rest = String(trimmed[trimmed.index(after: firstSpaceIdx)...])

            let cleanTokens = rest.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            var ppid: Int?
            var user = "unknown"
            var lstart: Date?
            var cwd: String?
            var args: String?

            if cleanTokens.count >= 1 {
                ppid = Int(cleanTokens[0])
            }
            if cleanTokens.count >= 2 {
                user = cleanTokens[1]
            }
            if cleanTokens.count >= 7 {
                let lstartStr = cleanTokens[2...6].joined(separator: " ")
                lstart = dateFormatter.date(from: lstartStr)
            }
            if cleanTokens.count >= 8 {
                cwd = cleanTokens[7]
                args = cleanTokens.dropFirst(8).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            }

            return PortProcess(
                port: 0,
                protocolName: "process",
                pid: pid,
                user: user,
                command: args?.split(separator: "/").last.map(String.init) ?? name,
                fullCommand: args,
                parentPID: ppid,
                startTime: lstart,
                workingDirectory: cwd
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

    public func killProcessByPID(_ pid: Int, force: Bool = false) throws {
        guard pid > 0 else {
            throw PortManagerError.invalidPID(pid)
        }
        let signal = force ? "KILL" : "TERM"
        _ = try runCommand("/bin/kill", arguments: ["-s", signal, "\(pid)"])
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

    func runCommand(_ path: String, arguments: [String], timeout: TimeInterval = 10) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        if process.isRunning {
            let deadline = DispatchTime.now() + timeout
            DispatchQueue.global().asyncAfter(deadline: deadline) {
                if process.isRunning {
                    process.terminate()
                }
            }
        }
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    func runCommandQuiet(_ path: String, arguments: [String], timeout: TimeInterval = 10) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try? process.run()

        let semaphore = DispatchSemaphore(value: 0)
        var didTimeout = false

        DispatchQueue.global().async {
            process.waitUntilExit()
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + timeout)
        didTimeout = process.isRunning

        if didTimeout {
            process.terminate()
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
