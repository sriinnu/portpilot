import Foundation

// MARK: - Port Process Model
public struct PortProcess: Codable, Hashable, Identifiable {
    public let port: Int
    public let protocolName: String
    public let pid: Int
    public let user: String
    public let command: String
    public var fullCommand: String?

    public var id: Int { port }

    public init(port: Int, protocolName: String, pid: Int, user: String, command: String, fullCommand: String? = nil) {
        self.port = port
        self.protocolName = protocolName
        self.pid = pid
        self.user = user
        self.command = command
        self.fullCommand = fullCommand
    }
}

// MARK: - Port Connection Model
public struct PortConnection: Codable, Hashable {
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

    public var errorDescription: String? {
        switch self {
        case .noProcessFound(let port):
            return "No process found listening on port \(port)"
        case .killFailed(let port, let reason):
            return "Failed to kill process on port \(port): \(reason)"
        case .parseFailed(let reason):
            return "Failed to parse output: \(reason)"
        }
    }
}

// MARK: - Port Manager
public final class PortManager {

    public init() {}

    // MARK: - Get Listening Processes

    public func getListeningProcesses(
        startPort: Int? = nil,
        endPort: Int? = nil,
        protocolFilter: String? = nil
    ) throws -> [PortProcess] {
        let output = try runCommand("/usr/sbin/lsof", arguments: ["-iTCP", "-iUDP", "-sTCP:LISTEN", "-P", "-n"])
        var processes: [PortProcess] = []
        var seen = Set<Int>()

        for line in output.components(separatedBy: "\n").dropFirst() {
            guard !line.isEmpty else { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 9 else { continue }

            let command = parts[0]
            guard let pid = Int(parts[1]) else { continue }
            let user = parts[2]

            // Parse name field for port (e.g., "*:8080" or "127.0.0.1:3000")
            let nameField = parts[8]
            guard let colonIndex = nameField.lastIndex(of: ":") else { continue }
            let portString = String(nameField[nameField.index(after: colonIndex)...])
            guard let port = Int(portString) else { continue }

            // Determine protocol
            let proto: String
            if line.contains("TCP") {
                proto = "tcp"
            } else if line.contains("UDP") {
                proto = "udp"
            } else {
                proto = "tcp"
            }

            // Apply filters
            if let start = startPort, port < start { continue }
            if let end = endPort, port > end { continue }
            if let filter = protocolFilter, proto.lowercased() != filter.lowercased() { continue }

            // Deduplicate by port
            guard !seen.contains(port) else { continue }
            seen.insert(port)

            processes.append(PortProcess(
                port: port,
                protocolName: proto,
                pid: pid,
                user: user,
                command: command
            ))
        }

        var sorted = processes.sorted { $0.port < $1.port }
        sorted = fetchFullCommands(for: sorted)
        return sorted
    }

    // MARK: - Fetch Full Commands

    private func fetchFullCommands(for processes: [PortProcess]) -> [PortProcess] {
        guard !processes.isEmpty else { return processes }

        let pids = processes.map { String($0.pid) }.joined(separator: ",")
        guard let output = try? runCommand("/bin/ps", arguments: ["-p", pids, "-o", "pid=,args="]) else {
            return processes
        }

        var pidToArgs: [Int: String] = [:]
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Format: "  PID ARGS..." — split on first whitespace run after pid
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let pid = Int(parts[0]) else { continue }
            pidToArgs[pid] = String(parts[1])
        }

        return processes.map { process in
            var updated = process
            updated.fullCommand = pidToArgs[process.pid]
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

    // MARK: - Categorize Port

    public func categorizePort(_ port: Int) -> PortCategory? {
        for category in PortCategory.allCases {
            if category.defaultPorts.contains(port) {
                return category
            }
        }
        return nil
    }

    // MARK: - Shell Command Runner

    private func runCommand(_ path: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
