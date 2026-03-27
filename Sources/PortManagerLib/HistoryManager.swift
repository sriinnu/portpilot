import Foundation

// MARK: - Port Usage Entry

public struct PortUsageEntry: Codable, Identifiable {
    public let id: UUID
    public let port: Int
    public let protocolName: String
    public let pid: Int
    public let command: String
    public let user: String
    public let firstSeen: Date
    public var lastSeen: Date

    public init(port: Int, protocolName: String, pid: Int, command: String, user: String) {
        self.id = UUID()
        self.port = port
        self.protocolName = protocolName
        self.pid = pid
        self.command = command
        self.user = user
        self.firstSeen = Date()
        self.lastSeen = Date()
    }

    public var formattedFirstSeen: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: firstSeen)
    }

    public var formattedLastSeen: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: lastSeen)
    }

    public var relativeFirstSeen: String {
        #if canImport(ObjectiveC)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: firstSeen, relativeTo: Date())
        #else
        let interval = Date().timeIntervalSince(firstSeen)
        if interval < 60 {
            return "\(Int(interval))s ago"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h ago"
        } else {
            return "\(Int(interval / 86400))d ago"
        }
        #endif
    }

    public var relativeLastSeen: String {
        #if canImport(ObjectiveC)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastSeen, relativeTo: Date())
        #else
        let interval = Date().timeIntervalSince(lastSeen)
        if interval < 60 {
            return "\(Int(interval))s ago"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h ago"
        } else {
            return "\(Int(interval / 86400))d ago"
        }
        #endif
    }
}

// MARK: - Port Stats

public struct PortStats {
    public let totalUniquePorts: Int
    public let mostUsedPorts: [(port: Int, count: Int)]
    public let frequentlyRestartedPorts: [(port: Int, restartCount: Int)]
    public let portHistory: [Int: [Date]]

    public init(totalUniquePorts: Int, mostUsedPorts: [(port: Int, count: Int)], frequentlyRestartedPorts: [(port: Int, restartCount: Int)], portHistory: [Int: [Date]]) {
        self.totalUniquePorts = totalUniquePorts
        self.mostUsedPorts = mostUsedPorts
        self.frequentlyRestartedPorts = frequentlyRestartedPorts
        self.portHistory = portHistory
    }
}

public struct HistoryEntry: Codable, Identifiable {
    public let id: UUID
    public let port: Int
    public let protocolName: String
    public let pid: Int
    public let command: String
    public let user: String
    public let killedAt: Date
    public var wasForceKilled: Bool
    public var duration: TimeInterval?

    public init(from process: PortProcess, wasForceKilled: Bool = false, startTime: Date? = nil) {
        self.id = UUID()
        self.port = process.port
        self.protocolName = process.protocolName
        self.pid = process.pid
        self.command = process.command
        self.user = process.user
        self.killedAt = Date()
        self.wasForceKilled = wasForceKilled
        self.duration = startTime.map { Date().timeIntervalSince($0) }
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: killedAt)
    }

    public var relativeTime: String {
        #if canImport(ObjectiveC)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: killedAt, relativeTo: Date())
        #else
        // Fallback for Linux/Windows - simple date difference
        let interval = Date().timeIntervalSince(killedAt)
        if interval < 60 {
            return "\(Int(interval))s ago"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h ago"
        } else {
            return "\(Int(interval / 86400))d ago"
        }
        #endif
    }
}

public struct HistoryStats {
    public let totalKills: Int
    public let forceKills: Int
    public let uniquePortsKilled: Int
    public let uniqueCommandsKilled: Int
    public let killsToday: Int

    public init(totalKills: Int, forceKills: Int, uniquePortsKilled: Int, uniqueCommandsKilled: Int, killsToday: Int) {
        self.totalKills = totalKills
        self.forceKills = forceKills
        self.uniquePortsKilled = uniquePortsKilled
        self.uniqueCommandsKilled = uniqueCommandsKilled
        self.killsToday = killsToday
    }
}

public final class HistoryManager: ObservableObject {
    private let userDefaults: UserDefaults
    private let historyKey = "portKiller.history"
    private let portUsageKey = "portKiller.portUsage"
    private let maxHistorySize = 500
    private let maxPortUsageSize = 1000
    private let lock = NSLock()

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Port Usage History

    public func recordPortUsage(port: Int, process: PortProcess) {
        lock.lock()
        defer { lock.unlock() }
        var usage = getAllPortUsage()

        // Check if we already have an entry for this port+pid combination
        if let existingIndex = usage.firstIndex(where: { $0.port == port && $0.pid == process.pid }) {
            // Update last seen
            usage[existingIndex].lastSeen = Date()
        } else {
            // Add new entry
            let entry = PortUsageEntry(
                port: port,
                protocolName: process.protocolName,
                pid: process.pid,
                command: process.command,
                user: process.user
            )
            usage.insert(entry, at: 0)
        }

        if usage.count > maxPortUsageSize {
            usage = Array(usage.prefix(maxPortUsageSize))
        }

        savePortUsage(usage)
    }

    public func getAllPortUsage() -> [PortUsageEntry] {
        guard let data = userDefaults.data(forKey: portUsageKey),
              let usage = try? JSONDecoder().decode([PortUsageEntry].self, from: data) else {
            return []
        }
        return usage
    }

    public func getPortUsage(forPort port: Int) -> [PortUsageEntry] {
        return getAllPortUsage().filter { $0.port == port }
    }

    public func getPortHistory(port: Int) -> [Date] {
        return getPortUsage(forPort: port).map { $0.lastSeen }.sorted()
    }

    public func getPortStats() -> PortStats {
        let usage = getAllPortUsage()

        // Count port occurrences
        var portCounts: [Int: Int] = [:]
        for entry in usage {
            portCounts[entry.port, default: 0] += 1
        }

        let mostUsed = portCounts
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { (port: $0.key, count: $0.value) }

        // Find frequently restarted ports (same port, different PID)
        var portPids: [Int: Set<Int>] = [:]
        for entry in usage {
            portPids[entry.port, default: Set()].insert(entry.pid)
        }

        let frequentlyRestarted = portPids
            .filter { $0.value.count > 1 }
            .map { (port: $0.key, restartCount: $0.value.count) }
            .sorted { $0.restartCount > $1.restartCount }
            .prefix(10)

        // Build port history
        var portHistory: [Int: [Date]] = [:]
        for entry in usage {
            if portHistory[entry.port] == nil {
                portHistory[entry.port] = []
            }
            portHistory[entry.port]?.append(entry.lastSeen)
        }

        return PortStats(
            totalUniquePorts: portCounts.count,
            mostUsedPorts: mostUsed,
            frequentlyRestartedPorts: Array(frequentlyRestarted),
            portHistory: portHistory
        )
    }

    public func clearPortUsage() {
        userDefaults.removeObject(forKey: portUsageKey)
    }

    public func clearPortUsage(forPort port: Int) {
        var usage = getAllPortUsage()
        usage.removeAll { $0.port == port }
        savePortUsage(usage)
    }

    private func savePortUsage(_ usage: [PortUsageEntry]) {
        if let data = try? JSONEncoder().encode(usage) {
            userDefaults.set(data, forKey: portUsageKey)
        }
    }

    // MARK: - CRUD Operations

    public func addEntry(from process: PortProcess, wasForceKilled: Bool = false, startTime: Date? = nil) {
        lock.lock()
        defer { lock.unlock() }
        var history = getAllHistory()
        let entry = HistoryEntry(from: process, wasForceKilled: wasForceKilled, startTime: startTime)
        history.insert(entry, at: 0)

        if history.count > maxHistorySize {
            history = Array(history.prefix(maxHistorySize))
        }

        saveHistory(history)
    }

    public func getAllHistory() -> [HistoryEntry] {
        guard let data = userDefaults.data(forKey: historyKey),
              let history = try? JSONDecoder().decode([HistoryEntry].self, from: data) else {
            return []
        }
        return history
    }

    public func getRecentHistory(limit: Int = 50) -> [HistoryEntry] {
        return Array(getAllHistory().prefix(limit))
    }

    public func getHistoryForPort(_ port: Int) -> [HistoryEntry] {
        return getAllHistory().filter { $0.port == port }
    }

    public func getHistoryForCommand(_ command: String) -> [HistoryEntry] {
        return getAllHistory().filter { $0.command.lowercased().contains(command.lowercased()) }
    }

    public func getHistoryInDateRange(from startDate: Date, to endDate: Date) -> [HistoryEntry] {
        return getAllHistory().filter { entry in
            entry.killedAt >= startDate && entry.killedAt <= endDate
        }
    }

    public func clearHistory() {
        userDefaults.removeObject(forKey: historyKey)
    }

    public func clearHistory(olderThan date: Date) {
        var history = getAllHistory()
        history.removeAll { $0.killedAt < date }
        saveHistory(history)
    }

    public func clearHistory(forPort port: Int) {
        var history = getAllHistory()
        history.removeAll { $0.port == port }
        saveHistory(history)
    }

    // MARK: - Statistics

    public func getKillCount() -> Int {
        return getAllHistory().count
    }

    public func getKillCount(forPort port: Int) -> Int {
        return getHistoryForPort(port).count
    }

    public func getMostKilledPorts(limit: Int = 10) -> [(port: Int, count: Int)] {
        var portCounts: [Int: Int] = [:]

        for entry in getAllHistory() {
            portCounts[entry.port, default: 0] += 1
        }

        return portCounts
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (port: $0.key, count: $0.value) }
    }

    public func getMostKilledCommands(limit: Int = 10) -> [(command: String, count: Int)] {
        var commandCounts: [String: Int] = [:]

        for entry in getAllHistory() {
            commandCounts[entry.command, default: 0] += 1
        }

        return commandCounts
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (command: $0.key, count: $0.value) }
    }

    public func getHistoryStats() -> HistoryStats {
        let history = getAllHistory()

        let totalKills = history.count
        let forceKills = history.filter { $0.wasForceKilled }.count

        var portsKilled = Set<Int>()
        var commandsKilled = Set<String>()

        for entry in history {
            portsKilled.insert(entry.port)
            commandsKilled.insert(entry.command)
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var killsToday = 0

        for entry in history {
            if calendar.startOfDay(for: entry.killedAt) == today {
                killsToday += 1
            }
        }

        return HistoryStats(
            totalKills: totalKills,
            forceKills: forceKills,
            uniquePortsKilled: portsKilled.count,
            uniqueCommandsKilled: commandsKilled.count,
            killsToday: killsToday
        )
    }

    // MARK: - Private

    private func saveHistory(_ history: [HistoryEntry]) {
        if let data = try? JSONEncoder().encode(history) {
            userDefaults.set(data, forKey: historyKey)
        }
    }
}
