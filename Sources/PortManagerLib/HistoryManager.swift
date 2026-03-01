import Foundation

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
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: killedAt, relativeTo: Date())
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

public final class HistoryManager {
    private let userDefaults: UserDefaults
    private let historyKey = "portKiller.history"
    private let maxHistorySize = 500

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - CRUD Operations

    public func addEntry(from process: PortProcess, wasForceKilled: Bool = false, startTime: Date? = nil) {
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

        var totalKills = history.count
        var forceKills = history.filter { $0.wasForceKilled }.count

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
