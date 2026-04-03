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

    /// Unique ID: combines protocol+port for network, protocol+pid for sockets
    public var id: String {
        if protocolName == "unix" { return "unix-\(pid)" }
        return "\(protocolName)-\(port)-\(pid)"
    }

    /// Whether this is a Unix socket process (no network port)
    public var isUnixSocket: Bool { protocolName == "unix" }

    public init(port: Int, protocolName: String, pid: Int, user: String, command: String, fullCommand: String? = nil, parentPID: Int? = nil, startTime: Date? = nil, workingDirectory: String? = nil, processPath: String? = nil, socketPath: String? = nil, cpuUsage: Double? = nil, memoryMB: Double? = nil) {
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
        // Use all available fields to build a deterministic unique ID, avoiding collisions when
        // multiple connections share the same remote/local address pair
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
        // Check for WSL
        if let version = try? String(contentsOfFile: "/proc/version", encoding: .utf8),
           version.lowercased().contains("microsoft") {
            return .wsl
        }
        // Check WSL2 environment variable
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

    // MARK: - Get PID for Port

    /// Get the process ID listening on a specific port
    public func getPID(forPort port: Int, protocol: String = "tcp") -> Int? {
        let processes = (try? getListeningProcesses(startPort: port, endPort: port, protocolFilter: `protocol`)) ?? []
        return processes.first?.pid
    }

    /// Get process IDs for multiple ports
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
            // Use ss for Linux/WSL - more reliable than netstat
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

        // Apply filters
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
        // Dedup by (protocol, port, pid) to allow multiple PIDs on the same port (SO_REUSEPORT)
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

        // ss -tlnp output format (column-based):
        // State    Recv-Q   Send-Q   Local Address:Port   Peer Address:Port   Process
        // LISTEN   0        511      127.0.0.1:631        0.0.0.0:*          users:(("cupsd",pid=449,fd=4))

        for line in output.components(separatedBy: "\n") {
            guard line.contains("LISTEN") else { continue }

            // Split into columns — ss uses whitespace-delimited columns
            let columns = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            // Expected: [State, Recv-Q, Send-Q, LocalAddr:Port, PeerAddr:Port, Process...]
            guard columns.count >= 5 else { continue }

            // Extract port from Local Address:Port (column index 3)
            let localAddr = columns[3]
            guard let lastColon = localAddr.lastIndex(of: ":") else { continue }
            let portString = String(localAddr[localAddr.index(after: lastColon)...])
            guard let port = Int(portString) else { continue }

            // Extract PID and command from process info column(s)
            // Format: users:(("command",pid=123,fd=x))
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

            // User: resolve from /proc/{pid}/status if available, else fall back to uid lookup
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

        // netstat -ano output format:
        //   TCP    0.0.0.0:8080    0.0.0.0:0    LISTENING    12345
        // Find PIDs first
        var portToPID: [Int: Int] = [:]

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("TCP") || trimmed.hasPrefix("UDP") else { continue }
            guard trimmed.contains("LISTENING") else { continue }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 5 else { continue }

            // Parse local address:port
            let localAddr = parts[1]
            guard let colonIndex = localAddr.lastIndex(of: ":") else { continue }
            let portString = String(localAddr[localAddr.index(after: colonIndex)...])
            guard let port = Int(portString) else { continue }

            let pid = Int(parts[4]) ?? 0
            portToPID[port] = pid
        }

        // Now get process names using tasklist
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

        // lstart format: "Wed Mar 19 15:30:00 2025" — parse into Date
        // ps lstart outputs in the system's local timezone
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"

        var pidToInfo: [Int: (args: String, ppid: Int?, lstart: Date?, cwd: String?)] = [:]
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Fields: pid ppid lstart cwd args...
            // lstart is a multi-word field (e.g. "Wed Mar 19 15:30:00 2025"), so we parse carefully.
            // Find first space after PID
            guard let firstSpaceIdx = trimmed.firstIndex(of: " ") else { continue }
            let pidStr = String(trimmed[..<firstSpaceIdx])
            guard let pid = Int(pidStr) else { continue }

            let rest = String(trimmed[trimmed.index(after: firstSpaceIdx)...])

            // Find ppid (next space-delimited token)
            let tokens = rest.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            var ppid: Int?
            var lstart: Date?
            var cwd: String?
            var args: String?

            // tokens[0] = ppid
            if tokens.count >= 1 {
                ppid = Int(tokens[0])
            }

            // tokens[1..<6] = lstart (5 words: "Wed" "Mar" "19" "15:30:00" "2025")
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

        // Fetch CPU + memory separately to avoid fragile multi-field parsing
        let stats = fetchProcessStats(pids: pids)

        // Get process paths for classification
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
            return updated
        }
    }

    /// Fetches CPU usage and memory (RSS in KB) for a comma-separated list of PIDs.
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
            memMap[pid] = rssKB / 1024.0 // Convert KB to MB
        }
        return (cpuMap, memMap)
    }

    private func fetchFullCommandsLinux(for processes: [PortProcess]) -> [PortProcess] {
        // On Linux/WSL, use ps with standard syntax
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

        // Fetch CPU + memory separately
        let stats = fetchProcessStats(pids: pids)

        // Resolve process path and working directory from /proc
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
            return updated
        }
    }

    private func fetchFullCommandsWindows(for processes: [PortProcess]) -> [PortProcess] {
        // On Windows, use wmic to get command line
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
            return updated
        }
    }

    // MARK: - Get Connections

    public func getConnections(for port: Int) throws -> [PortConnection] {
        let output = try runCommand("/usr/sbin/lsof", arguments: ["-iTCP:\(port)", "-P", "-n"])
        var connections: [PortConnection] = []

        for line in output.components(separatedBy: "\n").dropFirst() {
            guard !line.isEmpty else { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 10 else { continue }

            guard let pid = Int(parts[1]) else { continue }
            let nameField = parts[8]
            let state = parts.count > 9 ? parts[9].trimmingCharacters(in: CharacterSet(charactersIn: "()")) : "UNKNOWN"

            // Parse local->remote from name field
            let addressParts = nameField.components(separatedBy: "->")
            let localAddress = addressParts[0]
            let remoteAddress = addressParts.count > 1 ? addressParts[1] : "*"

            connections.append(PortConnection(
                localAddress: localAddress,
                remoteAddress: remoteAddress,
                state: state,
                pid: pid
            ))
        }

        return connections
    }

    // MARK: - Kill Process

    public func killProcessOnPort(_ port: Int, force: Bool = false, timeout: Int = 5000) throws {
        let processes = try getListeningProcesses(startPort: port, endPort: port)
        guard let process = processes.first else {
            throw PortManagerError.noProcessFound(port)
        }

        let signal = force ? "KILL" : "TERM"
        let result = try runCommand("/bin/kill", arguments: ["-s", signal, "\(process.pid)"])
        _ = result // kill usually has no output on success
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

    /// Find available ports in a range by attempting to bind to each port
    public func findAvailablePorts(startPort: Int? = nil, endPort: Int? = nil, count: Int = 1) throws -> [Int] {
        let start = startPort ?? 1024
        let end = endPort ?? 65535
        var availablePorts: [Int] = []

        // Get currently occupied ports to avoid false positives
        let occupiedPorts = Set((try getListeningProcesses()).map { $0.port })

        for port in start...end {
            guard availablePorts.count < count else { break }

            // Skip if port is already known to be occupied
            if occupiedPorts.contains(port) {
                continue
            }

            // Try to bind to the port
            if isPortAvailable(port) {
                availablePorts.append(port)
            }
        }

        return availablePorts
    }

    /// Check if a specific port is available by attempting to bind to it
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
        // Use lsof to check if port is in use
        let output = runCommandQuiet("/usr/sbin/lsof", arguments: ["-iTCP:\(port)", "-sTCP:LISTEN", "-P", "-n"])
        return output.isEmpty
    }

    private func checkPortAvailabilityWindows(_ port: Int) -> Bool {
        // Use netstat to check if port is in use
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

    private func runCommandQuiet(_ path: String, arguments: [String], timeout: TimeInterval = 10) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try? process.run()

        // Use a semaphore to implement actual timeout
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

    /// I resolve one parent process name by delegating to the batched lookup path.
    public func getParentProcessName(forPID pid: Int) -> String? {
        getParentProcessNames(forPIDs: [pid])[pid]
    }

    /// I resolve parent process names in one `ps` call so refresh stays off the hot path.
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

    /// Returns all processes matching any of the given process names (using pgrep or ps)
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
        // Use ps to find all processes matching the names
        var allProcesses: [PortProcess] = []

        // Try pgrep first for more accurate matching
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

        // Fallback: use ps to find all processes
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

                // Check if any of the names match
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

            // Find first space after PID
            guard let firstSpaceIdx = trimmed.firstIndex(of: " ") else { continue }
            let pidStr = String(trimmed[..<firstSpaceIdx])
            guard let pidVal = Int(pidStr), pidVal == pid else { continue }

            let rest = String(trimmed[trimmed.index(after: firstSpaceIdx)...])

            // ps format: ppid user lstart(5 words) cwd args...
            // Use omittingEmptySubsequences: true for reliable indexing
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
            // cleanTokens[2..<7] = lstart (5 words)
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

    /// Kill all processes matching any of the given names
    public func killAllProcesses(named names: [String], force: Bool = false) throws {
        let processes = getProcessesByName(names: names)
        for process in processes {
            let signal = force ? "KILL" : "TERM"
            _ = try runCommand("/bin/kill", arguments: ["-s", signal, "\(process.pid)"])
        }
    }

    /// Kill a process by its PID. Protected PIDs (0, 1, -1) are rejected.
    public func killProcessByPID(_ pid: Int, force: Bool = false) throws {
        // Reject protected PIDs
        guard pid > 0 else {
            throw PortManagerError.invalidPID(pid)
        }
        let signal = force ? "KILL" : "TERM"
        _ = try runCommand("/bin/kill", arguments: ["-s", signal, "\(pid)"])
    }

    // MARK: - Connection Blocklist

    /// Blocklist entry: loaded from ~/.portpilot/blocklist.txt
    /// Each line is a domain suffix, IP, or CIDR range to block.
    private struct BlocklistEntry: Sendable {
        let pattern: String
        let isCIDR: Bool

        init(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            self.pattern = trimmed
            // Simple CIDR detection: contains "/" and ends with a number
            self.isCIDR = trimmed.contains("/") && trimmed.rangeOfCharacter(from: .decimalDigits) != nil
        }

        func matches(_ remoteAddress: String, hostname: String?) -> Bool {
            // Extract host part from remote address (strip port)
            // Handle both IPv4 (1.2.3.4:port) and IPv6 ([::1]:port) formats
            let hostPart: String
            if remoteAddress.hasPrefix("[") {
                // IPv6 with brackets: [::1]:port
                if let closeBracket = remoteAddress.firstIndex(of: "]") {
                    hostPart = String(remoteAddress[remoteAddress.index(after: remoteAddress.startIndex)..<closeBracket])
                } else {
                    hostPart = remoteAddress
                }
            } else {
                // IPv4 or hostname: 1.2.3.4:port or hostname:port
                if let colonIdx = remoteAddress.lastIndex(of: ":") {
                    hostPart = String(remoteAddress[..<colonIdx])
                } else {
                    hostPart = remoteAddress
                }
            }

            // cleanHost is already stripped of brackets for IPv6
            let cleanHost = hostPart

            if isCIDR {
                return cidrContains(cidr: pattern, ip: cleanHost)
            }

            // Exact IP match
            if cleanHost == pattern {
                return true
            }

            // Domain/IP prefix match: "2a06:98c1:310b" matches "2a06:98c1:310b::ac40:9bd1"
            let lowerHost = cleanHost.lowercased()
            let lowerPattern = pattern.lowercased()
            if lowerHost == lowerPattern || lowerHost.hasSuffix("." + lowerPattern) || lowerHost.hasPrefix(lowerPattern + ":") {
                return true
            }

            // Hostname match (if resolved)
            if let hn = hostname?.lowercased() {
                if hn == lowerPattern || hn.hasSuffix("." + lowerPattern) {
                    return true
                }
            }

            return false
        }

        private func cidrContains(cidr: String, ip: String) -> Bool {
            let parts = cidr.split(separator: "/")
            guard parts.count == 2,
                  let prefix = Int(parts[1]),
                  prefix >= 0 && prefix <= 128 else { return false }

            let network = String(parts[0])
            return ipContainsPrefix(ip: ip, network: network, prefix: prefix)
        }

        private func ipContainsPrefix(ip: String, network: String, prefix: Int) -> Bool {
            guard let ipInt = parseIP(ip), let netInt = parseIP(network) else { return false }

            let mask: UInt32 = prefix == 0 ? 0 : ~((1 << (32 - prefix)) - 1)
            return (ipInt & mask) == (netInt & mask)
        }

        private func parseIP(_ ip: String) -> UInt32? {
            let octets = ip.split(separator: ".").compactMap { UInt32(String($0)) }
            guard octets.count == 4 else { return nil }
            return (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3]
        }
    }

    /// Loaded blocklist cache, thread-safe via actor-like pattern
    private var cachedBlocklist: [BlocklistEntry]? = nil
    private var blocklistCacheTime: Date? = nil
    private let blocklistCacheDuration: TimeInterval = 60 // re-read every 60s

    /// Path to the blocklist file
    private var blocklistPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.portpilot/blocklist.txt"
    }

    /// Load blocklist from ~/.portpilot/blocklist.txt
    private func loadBlocklist() -> [BlocklistEntry] {
        // Use cached value if fresh enough
        if let cached = cachedBlocklist, let cacheTime = blocklistCacheTime,
           Date().timeIntervalSince(cacheTime) < blocklistCacheDuration {
            return cached
        }

        let entries = loadBlocklistFromDisk()
        cachedBlocklist = entries
        blocklistCacheTime = Date()
        return entries
    }

    private func loadBlocklistFromDisk() -> [BlocklistEntry] {
        let path = blocklistPath
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }
        return content
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { BlocklistEntry($0) }
    }

    /// Check if a connection matches the blocklist
    public func isBlocklisted(connection: EstablishedConnection) -> Bool {
        let entries = loadBlocklist()
        for entry in entries {
            if entry.matches(connection.remoteAddress, hostname: connection.remoteHostname) {
                return true
            }
        }
        return false
    }

    /// Return all connections that match the blocklist
    public func blocklistedConnections(from all: [EstablishedConnection]) -> [EstablishedConnection] {
        return all.filter { isBlocklisted(connection: $0) }
    }

    // MARK: - Unix Socket Discovery

    /// Get processes listening on Unix domain sockets (macOS only)
    public func getUnixSocketProcesses() -> [PortProcess] {
        guard Platform.current == .macOS else { return [] }

        // lsof -U lists all Unix domain socket files
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

            // NAME is everything after the NODE column (index 7+)
            // handles paths with spaces
            let nameField = parts.count > 8
                ? parts[8...].joined(separator: " ")
                : (parts.last ?? "")

            // Skip anonymous sockets (hex pointers like ->0x...)
            guard nameField.contains("/") else { continue }

            // Deduplicate by PID (one entry per process, prefer .sock paths)
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

    // MARK: - Cronjob Discovery

    /// Get all cronjobs for the current user and system cron directories
    public func getCronjobs(userOnly: Bool = false, systemOnly: Bool = false) -> [CronjobEntry] {
        var entries: [CronjobEntry] = []

        let platform = Platform.current

        guard platform != .windows else { return [] }

        // User crontab
        if !systemOnly {
            let userCrons = getUserCronjobs()
            entries.append(contentsOf: userCrons)
        }

        // System cron files
        if !userOnly {
            let systemCrons = getSystemCronjobs()
            entries.append(contentsOf: systemCrons)
        }

        return entries.sorted { ($0.nextRun ?? .distantFuture) < ($1.nextRun ?? .distantFuture) }
    }

    /// Get cronjobs from the current user's crontab
    private func getUserCronjobs() -> [CronjobEntry] {
        let output = runCommandQuiet("/usr/bin/crontab", arguments: ["-l"])
        return parseCrontab(output: output, source: "user", user: currentUsername())
    }

    /// Get cronjobs from system cron directories
    private func getSystemCronjobs() -> [CronjobEntry] {
        var entries: [CronjobEntry] = []

        let cronDirs = ["/etc/crontab", "/etc/cron.d/", "/etc/cron.hourly/", "/etc/cron.daily/", "/etc/cron.weekly/", "/etc/cron.monthly/"]

        for cronPath in cronDirs {
            if cronPath.hasSuffix("/") {
                // Directory — read all files
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
                // Single file
                if let content = try? String(contentsOfFile: cronPath, encoding: .utf8) {
                    entries.append(contentsOf: parseCrontab(output: content, source: cronPath, user: extractUserFromCrontab(fullPath: cronPath, line: nil)))
                }
            }
        }

        return entries
    }

    /// Parse crontab output into CronjobEntry objects
    private func parseCrontab(output: String, source: String, user: String?) -> [CronjobEntry] {
        var entries: [CronjobEntry] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard !trimmed.hasPrefix("#") else { continue }

            // Check if this is a system crontab with user field (6 fields instead of 5)
            // Format: minute hour day month weekday [user] command
            let components = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

            var scheduleWords: [String]
            var command: String
            var effectiveUser: String?

            if components.count >= 7 {
                // System crontab format: minute hour day month weekday user command
                scheduleWords = Array(components[0..<5])
                effectiveUser = components[5]
                command = components.dropFirst(6).joined(separator: " ")
            } else if components.count >= 6 {
                // Likely: minute hour day month weekday command
                scheduleWords = Array(components[0..<5])
                command = components.dropFirst(5).joined(separator: " ")
                effectiveUser = user
            } else if components.count == 5 {
                // All schedule fields but no command — skip
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
    private func extractUserFromCrontab(fullPath: String, line: String?) -> String? {
        // /etc/crontab typically has a user field after the schedule fields
        // Example: "0 * * * * root /some/command"
        if fullPath == "/etc/crontab" {
            // Try to read the first non-comment, non-empty line
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
    private func currentUsername() -> String {
        return ProcessInfo.processInfo.userName
    }

    /// Convert a cron schedule to human-readable format
    private func humanReadableSchedule(_ schedule: String) -> String {
        let parts = schedule.split(separator: " ").map(String.init)
        guard parts.count >= 5 else { return schedule }

        let min = parts[0], hour = parts[1], dom = parts[2], month = parts[3], dow = parts[4]

        // Every minute
        if min == "*" && hour == "*" && dom == "*" && month == "*" && dow == "*" {
            return "Every minute"
        }

        // Every N minutes
        if min.hasPrefix("*/") {
            let interval = String(min.dropFirst(2))
            return "Every \(interval) min"
        }

        // Every N hours
        if min == "0" && hour.hasPrefix("*/") {
            let interval = String(hour.dropFirst(2))
            return "Every \(interval)h"
        }

        // Daily at specific time: "0 14 * * *"
        if min != "*" && hour != "*" && dom == "*" && month == "*" && dow == "*" {
            return "Daily @ \(hour):\(min.padding(toLength: 2, withPad: "0", startingAt: 0))"
        }

        // Weekly
        if dom == "*" && month == "*" && dow != "*" {
            let dayName = dayOfWeekName(dow)
            return "Weekly on \(dayName) @ \(hour):\(min.padding(toLength: 2, withPad: "0", startingAt: 0))"
        }

        // Monthly
        if dom != "*" && month == "*" && dow == "*" {
            return "Monthly on day \(dom) @ \(hour):\(min.padding(toLength: 2, withPad: "0", startingAt: 0))"
        }

        return schedule
    }

    /// Get day of week name from number
    private func dayOfWeekName(_ dow: String) -> String {
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        if let num = Int(dow), num >= 0, num < 7 {
            return days[num]
        }
        // Handle names like "Mon-Fri"
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
        let maxIterations = 525600 // one year of minutes

        for _ in 0..<maxIterations {
            current = calendar.date(byAdding: .minute, value: 1, to: current)!

            let components = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: current)

            guard let min = components.minute, matchesCronField(min, pattern: minPart) else { continue }
            guard let hour = components.hour, matchesCronField(hour, pattern: hourPart) else { continue }
            guard let month = components.month, matchesCronField(month, pattern: monthPart) else { continue }

            // Day of month and day of week — cron uses OR logic (either matches)
            let domMatches = domPart == "*" || matchesCronField(components.day ?? 0, pattern: domPart)
            let dowMatches = dowPart == "*" || matchesCronField(components.weekday ?? 0, pattern: dowPart)

            if (domPart == "*" && dowPart == "*") || (domMatches && dowMatches) || (domMatches && dowPart == "*") || (domPart == "*" && dowMatches) {
                // Reset seconds
                var finalComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: current)
                finalComponents.second = 0
                return calendar.date(from: finalComponents)
            }
        }

        return nil
    }

    /// Match a cron field value against a pattern (supports *, */n, n, n-m, n,m)
    private func matchesCronField(_ value: Int, pattern: String) -> Bool {
        if pattern == "*" { return true }

        // Step pattern: */n
        if pattern.hasPrefix("*/") {
            if let step = Int(String(pattern.dropFirst(2))) {
                return value % step == 0
            }
        }

        // Range pattern: n-m
        if pattern.contains("-") {
            let rangeParts = pattern.split(separator: "-").map(String.init)
            if rangeParts.count == 2, let min = Int(rangeParts[0]), let max = Int(rangeParts[1]) {
                return value >= min && value <= max
            }
        }

        // List pattern: n,m
        if pattern.contains(",") {
            let listParts = pattern.split(separator: ",").map { String($0) }
            for part in listParts {
                if matchesCronField(value, pattern: part) { return true }
            }
            return false
        }

        // Single value
        if let intValue = Int(pattern) {
            return value == intValue
        }

        return false
    }

    // MARK: - All Connections Discovery

    /// Get all established network connections across all processes
    public func getAllConnections() throws -> [EstablishedConnection] {
        let platform = Platform.current
        let output: String

        switch platform {
        case .macOS:
            // Get all network connections including established TCP
            output = try runCommand("/usr/sbin/lsof", arguments: ["-i", "-P", "-n"])
        case .linux, .wsl:
            // ss -tnp gives all TCP connections without listening filter
            output = try runCommand("/usr/bin/ss", arguments: ["-tnp"])
        case .windows:
            output = try runCommand("netstat", arguments: ["-ano"])
        }

        var connections: [EstablishedConnection] = []

        switch platform {
        case .macOS:
            connections = parseMacOSAllConnections(output)
        case .linux, .wsl:
            connections = parseLinuxAllConnections(output)
        case .windows:
            connections = try parseWindowsAllConnections(output)
        }

        // Enrich with process names and blocklist status
        return enrichConnections(connections)
    }

    /// Parse macOS lsof -i -P -n output for all connections
    private func parseMacOSAllConnections(_ output: String) -> [EstablishedConnection] {
        var connections: [EstablishedConnection] = []
        var seen = Set<String>()

        for line in output.components(separatedBy: "\n").dropFirst() {
            guard !line.isEmpty else { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 9 else { continue }

            let command = parts[0]
            guard let pid = Int(parts[1]) else { continue }
            let user = parts[2]
            let nameField = parts.count > 8 ? parts[8] : ""

            // Parse NAME field: local->remote (STATE)
            // Format: *:port IP:port (STATE) or *:port (STATE)
            // or: localIP:localPort->remoteIP:remotePort (STATE)

            let stateMatch = nameField.range(of: #"\(([^)]+)\)"#, options: .regularExpression)
            let state = stateMatch.map { String(String(nameField[$0]).dropFirst().dropLast()) } ?? "UNKNOWN"
            let nameOnly = stateMatch.map { String(nameField[..<$0.lowerBound]) } ?? nameField

            // Skip LISTEN connections (we only want established outbound)
            if state.lowercased() == "listen" { continue }

            let addressParts = nameOnly.components(separatedBy: "->")
            let localAddress = addressParts.first ?? "*"
            let remoteAddress = addressParts.count > 1 ? addressParts[1] : "*"

            // Skip entries with no remote address (listening sockets with no connection)
            guard remoteAddress != "*" else { continue }

            let key = "\(pid)-\(remoteAddress)-\(localAddress)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            connections.append(EstablishedConnection(
                localAddress: localAddress,
                remoteAddress: remoteAddress,
                state: state,
                pid: pid,
                processName: command,
                user: user
            ))
        }

        return connections
    }

    /// Parse Linux ss -tnp output for all TCP connections
    private func parseLinuxAllConnections(_ output: String) -> [EstablishedConnection] {
        // First pass: collect (pid, localAddr, peerAddr, command) without resolving users
        struct RawConnection {
            let pid: Int
            let localAddr: String
            let peerAddr: String
            let command: String
        }
        var rawConnections: [RawConnection] = []

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard trimmed.contains("ESTAB") else { continue }

            // ss -tnp output format:
            // State    Recv-Q   Send-Q   Local Address:Port   Peer Address:Port   Process
            // ESTAB    0        0        192.168.1.5:52341    52.45.119.88:443     users:(("chrome",pid=1234,fd=20))

            let columns = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard columns.count >= 4 else { continue }

            let localAddr = columns[3]
            let peerAddr = columns.count >= 5 ? columns[4] : ""

            // Extract PID and command from process column(s)
            let processInfo = columns.dropFirst(5).joined(separator: " ")
            var pid = 0
            var command = "unknown"

            if let pidRange = processInfo.range(of: #"pid=(\d+)"#, options: .regularExpression) {
                let pidStr = String(processInfo[pidRange]).replacingOccurrences(of: "pid=", with: "")
                pid = Int(pidStr) ?? 0
            }
            if let cmdRange = processInfo.range(of: #"\"([^\"]+)\""#, options: .regularExpression) {
                command = String(processInfo[cmdRange])
                    .replacingOccurrences(of: "\"", with: "")
            }

            rawConnections.append(RawConnection(pid: pid, localAddr: localAddr, peerAddr: peerAddr, command: command))
        }

        // Batch UID resolution: collect unique PIDs and read all their /proc/{pid}/status at once
        let uniquePids = Array(Set(rawConnections.filter { $0.pid > 0 }.map { $0.pid }))
        var uidCache: [Int: String] = [:]  // pid -> username

        for pid in uniquePids {
            if let uid = getUidForPid(pid), let username = resolveUsername(uid: uid) {
                uidCache[pid] = username
            }
        }

        // Build final connections using cached UIDs
        var seen = Set<String>()
        var connections: [EstablishedConnection] = []
        for raw in rawConnections {
            // Deduplicate using same approach as macOS
            let id = "\(raw.pid)-\(raw.peerAddr)-\(raw.localAddr)"
            if seen.contains(id) { continue }
            seen.insert(id)

            let user = raw.pid > 0 ? (uidCache[raw.pid] ?? "unknown") : "unknown"

            connections.append(EstablishedConnection(
                localAddress: raw.localAddr,
                remoteAddress: raw.peerAddr,
                state: "ESTABLISHED",
                pid: raw.pid,
                processName: raw.command,
                user: user
            ))
        }

        return connections
    }

    /// Parse Windows netstat -ano output for all TCP connections
    private func parseWindowsAllConnections(_ output: String) throws -> [EstablishedConnection] {
        var connections: [EstablishedConnection] = []

        // Get PID to process name mapping
        let tasklistOutput = try runCommand("tasklist", arguments: ["/FO", "CSV", "/NH"])
        var pidToName: [Int: String] = [:]
        for line in tasklistOutput.components(separatedBy: "\n") {
            let parts = line.split(separator: ",").map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            guard parts.count >= 2 else { continue }
            if let pid = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                pidToName[pid] = parts[0]
            }
        }

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("TCP") else { continue }
            guard trimmed.contains("ESTABLISHED") else { continue }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 5 else { continue }

            let localAddr = parts[1]
            let remoteAddr = parts[2]
            guard let pid = Int(parts[4]) else { continue }
            let processName = pidToName[pid] ?? "unknown"

            connections.append(EstablishedConnection(
                localAddress: localAddr,
                remoteAddress: remoteAddr,
                state: "ESTABLISHED",
                pid: pid,
                processName: processName,
                user: "unknown"
            ))
        }

        return connections
    }

    /// Enrich connections with blocklist status.
    /// Connection counts are computed at the caller level by grouping by PID.
    private func enrichConnections(_ connections: [EstablishedConnection]) -> [EstablishedConnection] {
        return connections.map { conn in
            var enriched = conn
            enriched.isBlocklisted = isBlocklisted(connection: conn)
            return enriched
        }
    }

    /// Get UID for a PID on Linux
    private func getUidForPid(_ pid: Int) -> Int? {
        guard let statusOutput = try? runCommand("/bin/cat", arguments: ["/proc/\(pid)/status"]) else { return nil }
        guard let uidLine = statusOutput.components(separatedBy: "\n").first(where: { $0.hasPrefix("Uid:") }) else { return nil }
        let uidParts = uidLine.split(separator: "\t", omittingEmptySubsequences: true)
        guard uidParts.count >= 2 else { return nil }
        return Int(uidParts[1])
    }

    /// Resolve username from UID on Linux
    private func resolveUsername(uid: Int) -> String? {
        if let passwdLine = try? runCommand("/usr/bin/id", arguments: ["-nu", String(uid)]) {
            return passwdLine.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    // MARK: - Shell Command Runner

    private func runCommand(_ path: String, arguments: [String], timeout: TimeInterval = 10) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        // I merge stderr into stdout so large `lsof` output cannot deadlock on an unread pipe.
        process.standardError = pipe

        try process.run()

        // Read data with timeout to prevent hanging on stuck processes
        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        if process.isRunning {
            // Give it the timeout window, then force-terminate
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
}
