import Foundation

// MARK: - Connection Discovery & Blocklist

extension PortManager {

    // MARK: - Get Connections for Port

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

    // MARK: - All Connections Discovery

    /// Get all established network connections across all processes
    public func getAllConnections() throws -> [EstablishedConnection] {
        let platform = Platform.current
        let output: String

        switch platform {
        case .macOS:
            output = try runCommand("/usr/sbin/lsof", arguments: ["-i", "-P", "-n"])
        case .linux, .wsl:
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

        return enrichConnections(connections)
    }

    /// Parse macOS lsof -i -P -n output for all connections
    func parseMacOSAllConnections(_ output: String) -> [EstablishedConnection] {
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

            let stateMatch = nameField.range(of: #"\(([^)]+)\)"#, options: .regularExpression)
            let state = stateMatch.map { String(String(nameField[$0]).dropFirst().dropLast()) } ?? "UNKNOWN"
            let nameOnly = stateMatch.map { String(nameField[..<$0.lowerBound]) } ?? nameField

            if state.lowercased() == "listen" { continue }

            let addressParts = nameOnly.components(separatedBy: "->")
            let localAddress = addressParts.first ?? "*"
            let remoteAddress = addressParts.count > 1 ? addressParts[1] : "*"

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
    func parseLinuxAllConnections(_ output: String) -> [EstablishedConnection] {
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

            let columns = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard columns.count >= 4 else { continue }

            let localAddr = columns[3]
            let peerAddr = columns.count >= 5 ? columns[4] : ""

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

        let uniquePids = Array(Set(rawConnections.filter { $0.pid > 0 }.map { $0.pid }))
        var uidCache: [Int: String] = [:]

        for pid in uniquePids {
            if let uid = getUidForPid(pid), let username = resolveUsername(uid: uid) {
                uidCache[pid] = username
            }
        }

        var seen = Set<String>()
        var connections: [EstablishedConnection] = []
        for raw in rawConnections {
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
    func parseWindowsAllConnections(_ output: String) throws -> [EstablishedConnection] {
        var connections: [EstablishedConnection] = []

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

    /// Enrich connections with blocklist status
    func enrichConnections(_ connections: [EstablishedConnection]) -> [EstablishedConnection] {
        return connections.map { conn in
            var enriched = conn
            enriched.isBlocklisted = isBlocklisted(connection: conn)
            return enriched
        }
    }

    /// Get UID for a PID on Linux
    func getUidForPid(_ pid: Int) -> Int? {
        guard let statusOutput = try? runCommand("/bin/cat", arguments: ["/proc/\(pid)/status"]) else { return nil }
        guard let uidLine = statusOutput.components(separatedBy: "\n").first(where: { $0.hasPrefix("Uid:") }) else { return nil }
        let uidParts = uidLine.split(separator: "\t", omittingEmptySubsequences: true)
        guard uidParts.count >= 2 else { return nil }
        return Int(uidParts[1])
    }

    /// Resolve username from UID on Linux
    func resolveUsername(uid: Int) -> String? {
        if let passwdLine = try? runCommand("/usr/bin/id", arguments: ["-nu", String(uid)]) {
            return passwdLine.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    // MARK: - Connection Blocklist

    /// Blocklist entry: loaded from ~/.portpilot/blocklist.txt
    struct BlocklistEntry: Sendable {
        let pattern: String
        let isCIDR: Bool

        init(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            self.pattern = trimmed
            self.isCIDR = trimmed.contains("/") && trimmed.rangeOfCharacter(from: .decimalDigits) != nil
        }

        func matches(_ remoteAddress: String, hostname: String?) -> Bool {
            let hostPart: String
            if remoteAddress.hasPrefix("[") {
                if let closeBracket = remoteAddress.firstIndex(of: "]") {
                    hostPart = String(remoteAddress[remoteAddress.index(after: remoteAddress.startIndex)..<closeBracket])
                } else {
                    hostPart = remoteAddress
                }
            } else {
                if let colonIdx = remoteAddress.lastIndex(of: ":") {
                    hostPart = String(remoteAddress[..<colonIdx])
                } else {
                    hostPart = remoteAddress
                }
            }

            let cleanHost = hostPart

            if isCIDR {
                return cidrContains(cidr: pattern, ip: cleanHost)
            }

            if cleanHost == pattern {
                return true
            }

            let lowerHost = cleanHost.lowercased()
            let lowerPattern = pattern.lowercased()
            if lowerHost == lowerPattern || lowerHost.hasSuffix("." + lowerPattern) || lowerHost.hasPrefix(lowerPattern + ":") {
                return true
            }

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

    /// Load blocklist from ~/.portpilot/blocklist.txt
    func loadBlocklist() -> [BlocklistEntry] {
        if let cached = cachedBlocklist as? [BlocklistEntry], let cacheTime = blocklistCacheTime,
           Date().timeIntervalSince(cacheTime) < blocklistCacheDuration {
            return cached
        }

        let entries = loadBlocklistFromDisk()
        cachedBlocklist = entries
        blocklistCacheTime = Date()
        return entries
    }

    func loadBlocklistFromDisk() -> [BlocklistEntry] {
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
}
