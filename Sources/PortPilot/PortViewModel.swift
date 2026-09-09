import Foundation
import Combine
import AppKit
import SwiftUI

// MARK: - Connection Type
enum ConnectionType: String, CaseIterable, Identifiable {
    case local = "Local"
    case database = "Database"
    case kubernetes = "Kubernetes"
    case cloudflare = "Cloudflare"
    case ssh = "SSH"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .local: return Theme.Icon.local
        case .database: return Theme.Icon.database
        case .kubernetes: return Theme.Icon.kubernetes
        case .cloudflare: return Theme.Icon.cloudflare
        case .ssh: return Theme.Icon.ssh
        }
    }

    var color: Color {
        switch self {
        case .local: return Theme.Section.local
        case .database: return Theme.Section.database
        case .kubernetes: return Theme.Section.kubernetes
        case .cloudflare: return Theme.Section.cloudflare
        case .ssh: return Theme.Section.ssh
        }
    }
}

// MARK: - Filter Category
enum FilterCategory: String, CaseIterable, Identifiable {
    case all = "All Ports"
    case web = "Web"
    case database = "Database"
    case dev = "Dev"
    case system = "System"
    case favorites = "Favorites"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "network"
        case .web: return "globe"
        case .database: return "cylinder"
        case .dev: return "hammer"
        case .system: return "gearshape.2"
        case .favorites: return "star.fill"
        }
    }
}

// MARK: - Source Filter
enum PortSourceFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case database = "Database"
    case orbstack = "OrbStack"
    case tunnels = "Tunnels"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        // Chrome derives from the ConnectionType each filter fronts — one
        // icon/color table in ConnectionType, not a drifting copy here.
        case .database: return ConnectionType.database.icon
        case .orbstack: return Theme.Icon.orbstack
        case .tunnels: return ConnectionType.ssh.icon
        }
    }

    var color: Color {
        switch self {
        case .all: return Theme.Badge.accentBackground
        case .database: return ConnectionType.database.color
        case .orbstack: return Theme.Section.orbstack
        case .tunnels: return ConnectionType.ssh.color
        }
    }

    /// I keep the pill label compact so the source switcher reads like tabs.
    var shortLabel: String {
        switch self {
        case .all: return "All"
        case .database: return "DB"
        case .orbstack: return "OrbStack"
        case .tunnels: return "Tunnels"
        }
    }
}

// MARK: - Port Mapping Info
struct PortMappingInfo {
    let localPort: Int
    let remotePort: Int?
    let remoteHost: String?
    let protocolName: String
}

/// I carry one immutable refresh result from background discovery back to the UI.
private struct PortRefreshSnapshot: Sendable {
    let processes: [PortProcess]
    let parentProcessNames: [Int: String]
    let totalPorts: Int
    let totalSockets: Int
}

// MARK: - Port View Model
@MainActor
class PortViewModel: ObservableObject {
    @Published var ports: [PortProcess] = []
    @Published var filteredPorts: [PortProcess] = []
    @Published var selectedPort: PortProcess?
    @Published var selectedPorts: Set<PortProcess> = []
    @Published var connections: [PortConnection] = []
    @Published var isLoadingConnections: Bool = false

    // Established connections (for Connections tab)
    @Published var allConnections: [EstablishedConnection] = []
    @Published var isLoadingAllConnections: Bool = false
    /// Cached grouped connections - updated whenever allConnections changes
    @Published private var connectionsGroupedCache: [(processName: String, connections: [EstablishedConnection], totalCount: Int)] = []

    // Cronjobs (for Schedules tab)
    @Published var cronjobs: [CronjobEntry] = []
    @Published var isLoadingCronjobs: Bool = false
    @Published var cronRunHistory: [String: CronRunRecord] = [:]
    @Published var runningCronjobIDs: Set<String> = []

    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    /// The one auto-dismiss timer for errorMessage. The model owns error
    /// consumption — two UI surfaces (main-window alert, dropdown banner)
    /// used to fight over one string, and a stale banner timer could wipe a
    /// fresh error (or dismiss the alert mid-read).
    private var errorConsumeTask: Task<Void, Never>?

    /// Surface an error to whichever surface is visible. Exactly one
    /// consume timer runs at a time; a new error cancels the previous timer
    /// instead of racing it.
    func raiseError(_ message: String) {
        errorMessage = message
        errorConsumeTask?.cancel()
        errorConsumeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.errorMessage = nil
        }
    }

    /// Clear the current error and stop its timer (manual dismiss).
    func dismissError() {
        errorConsumeTask?.cancel()
        errorConsumeTask = nil
        errorMessage = nil
    }
    @Published var successMessage: String?
    @Published var lastRefresh: Date?

    // Logs
    @Published var logs: [LogEntry] = []

    // Proxy sessions
    @Published var proxySessions: [ProxySession] = []
    @Published var isProxySheetPresented: Bool = false

    @Published var selectedProtocol: ProtocolFilter = .tcp {
        didSet { applyFilters() }
    }
    @Published var portRangeStart: String = ""
    @Published var portRangeEnd: String = ""
    @Published var forceKill: Bool = false
    @Published var searchText: String = "" {
        didSet { applyFilters() }
    }
    @Published var selectedCategory: FilterCategory = .all {
        didSet { applyFilters() }
    }
    @Published var selectedSourceFilter: PortSourceFilter = .all {
        didSet { applyFilters() }
    }
    @Published var hideSystemProcesses: Bool = false {
        didSet { applyFilters() }
    }

    @Published var selectedCustomProgram: CustomProgram? = nil

    private let portManager = PortManager()
    private var allPortsCache: [PortProcess] = []
    private var parentProcessNameCache: [Int: String] = [:]
    /// connectionType(for:) results, keyed by PortProcess.id. Cleared on refresh.
    private var connectionTypeCache: [String: ConnectionType] = [:]
    private var latestRefreshID = UUID()
    private var latestAllConnectionsRefreshID = UUID()

    @Published private(set) var favorites: Set<Int> = []
    @Published private(set) var connectionNames: [String: String] = [:]

    enum ProtocolFilter: String, CaseIterable {
        case tcp = "TCP"
        case udp = "UDP"
        case unix = "Unix"
        case all = "All"
    }

    init() {
        loadFavorites()
        loadConnectionNames()
        refreshPorts()
        setupProxyCallbacks()
        setupCronRunCallbacks()
    }

    var portCount: Int { filteredPorts.count }
    var totalCount: Int { allPortsCache.count }

    var categoryCounts: [FilterCategory: Int] {
        [
            .all: allPortsCache.count,
            .web: allPortsCache.filter { categorizePort($0) == .web }.count,
            .database: allPortsCache.filter { categorizePort($0) == .database }.count,
            .dev: allPortsCache.filter { categorizePort($0) == .dev }.count,
            .system: allPortsCache.filter { categorizePort($0) == .system }.count,
            .favorites: allPortsCache.filter { favorites.contains($0.port) }.count
        ]
    }

    /// I expose source counts so the UI can surface dedicated source tabs without extra work.
    var sourceCounts: [PortSourceFilter: Int] {
        [
            .all: allPortsCache.count,
            .database: allPortsCache.filter { matchesSourceFilter(.database, for: $0) }.count,
            .orbstack: allPortsCache.filter { matchesSourceFilter(.orbstack, for: $0) }.count,
            .tunnels: allPortsCache.filter { matchesSourceFilter(.tunnels, for: $0) }.count
        ]
    }

    // MARK: - Port Grouping

    /// Group ports by connection type based on process and full command.
    var groupedPorts: [ConnectionType: [PortProcess]] {
        Dictionary(grouping: filteredPorts) { connectionType(for: $0) }
    }

    // MARK: - Tunnel Detection

    /// Known database process names
    static let databaseProcesses: Set<String> = [
        "postgres", "postmaster", "pg_ctl",      // PostgreSQL
        "mysqld", "mariadb",                     // MySQL/MariaDB
        "mongod", "mongos",                      // MongoDB
        "redis-server", "redis-cli", "redis-sentinel",  // Redis
        "memcached",                             // Memcached
        "sqlserver",                             // SQL Server
        "oracle",                                // Oracle
        "cassandra",                             // Cassandra
        "cockroach",                             // CockroachDB
        "neo4j",                                 // Neo4j
        "influxd",                               // InfluxDB
        "clickhouse-server",                     // ClickHouse
        "duckdb",                                // DuckDB
        "qdrant",                                // Qdrant vector DB
        "weaviate",                              // Weaviate vector DB
        "milvus",                                // Milvus vector DB
        "pgbouncer",                             // PgBouncer connection pooler
        "haproxy",                               // HAProxy
    ]

    func connectionType(for port: PortProcess) -> ConnectionType {
        // Scans fullCommand with a dozen contains() per call — and rows call
        // it twice per render (icon + color). Cached per data snapshot.
        if let cached = connectionTypeCache[port.id] {
            return cached
        }
        let resolved = resolveConnectionType(for: port)
        connectionTypeCache[port.id] = resolved
        return resolved
    }

    private func resolveConnectionType(for port: PortProcess) -> ConnectionType {
        let basename = port.command.lowercased()
        let full = (port.fullCommand ?? "").lowercased()

        // Check for database processes first
        if Self.databaseProcesses.contains(basename) {
            return .database
        }

        // Check full command for database patterns
        for dbProcess in Self.databaseProcesses {
            if full.contains(dbProcess) {
                return .database
            }
        }

        switch basename {
        case "cloudflared":
            return .cloudflare
        case "kubectl":
            return .kubernetes
        case "ssh":
            return .ssh
        default:
            // Also check fullCommand for tunnel patterns
            if full.contains("kubectl") && full.contains("port-forward") {
                return .kubernetes
            }
            if full.contains("ssh") && (full.contains(" -l ") || full.contains(" -r ") || full.contains(" -d ")) {
                return .ssh
            }
            if full.contains("cloudflared") && (full.contains("tunnel") || full.contains("access")) {
                return .cloudflare
            }
            return .local
        }
    }

    func tunnelName(for port: PortProcess) -> String? {
        guard let full = port.fullCommand else { return nil }
        let type = connectionType(for: port)

        switch type {
        case .ssh:
            // Extract remote host: look for user@host or bare host argument
            let tokens = full.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            for token in tokens {
                if token.contains("@") && !token.hasPrefix("-") {
                    // user@remote-host → "remote-host"
                    let parts = token.split(separator: "@", maxSplits: 1)
                    if parts.count == 2 {
                        return String(parts[1])
                    }
                }
            }
            return nil

        case .kubernetes:
            // Extract resource name: port-forward (svc|pod|deploy)/name → name
            if let range = full.range(of: #"port-forward\s+(?:svc|pod|deploy|service|deployment)/(\S+)"#, options: .regularExpression) {
                let match = String(full[range])
                let parts = match.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 2 {
                    let resource = String(parts[1])
                    // Extract just the name after the /
                    if let slashIdx = resource.firstIndex(of: "/") {
                        return String(resource[resource.index(after: slashIdx)...])
                    }
                }
            }
            return nil

        case .cloudflare:
            // Extract tunnel name: tunnel run <name> → name
            if let range = full.range(of: #"tunnel\s+run\s+(\S+)"#, options: .regularExpression) {
                let match = String(full[range])
                let name = match.split(separator: " ").last.map(String.init)
                return name
            }
            // Extract hostname: --hostname <host>
            if let range = full.range(of: #"--hostname\s+(\S+)"#, options: .regularExpression) {
                let match = String(full[range])
                let host = match.split(separator: " ").last.map(String.init)
                return host
            }
            return nil

        case .database:
            return nil
        case .local:
            return nil
        }
    }

    func tunnelDetail(for port: PortProcess) -> String? {
        guard let full = port.fullCommand else { return nil }
        let type = connectionType(for: port)

        switch type {
        case .ssh:
            return parseSSHTunnelDetail(full)
        case .kubernetes:
            return parseKubectlTunnelDetail(full)
        case .cloudflare:
            return parseCloudflareTunnelDetail(full)
        case .database:
            return port.command
        case .local:
            return nil
        }
    }

    func kubeNamespace(for port: PortProcess) -> String {
        guard let full = port.fullCommand else { return "default" }
        let tokens = full.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        for (i, token) in tokens.enumerated() {
            if (token == "-n" || token == "--namespace") && i + 1 < tokens.count {
                return tokens[i + 1]
            }
        }
        return "default"
    }

    func portMappingInfo(for port: PortProcess) -> PortMappingInfo {
        guard let full = port.fullCommand else {
            return PortMappingInfo(localPort: port.port, remotePort: nil, remoteHost: nil, protocolName: port.protocolName)
        }
        let type = connectionType(for: port)

        switch type {
        case .ssh:
            // Parse -L localPort:host:remotePort
            if let range = full.range(of: #"-[LR]\s+(\S+)"#, options: .regularExpression) {
                let match = String(full[range])
                let spec = match.drop(while: { $0 != " " }).trimmingCharacters(in: .whitespaces)
                let parts = spec.split(separator: ":")
                if parts.count >= 3 {
                    let remoteHost = String(parts[1])
                    let remotePort = Int(parts[2])
                    return PortMappingInfo(localPort: port.port, remotePort: remotePort, remoteHost: remoteHost, protocolName: port.protocolName)
                }
            }

        case .kubernetes:
            // Parse port-forward ... localPort:remotePort
            if let range = full.range(of: #"port-forward\s+\S+\s+(\d+):(\d+)"#, options: .regularExpression) {
                let match = String(full[range])
                let tokens = match.split(separator: " ", omittingEmptySubsequences: true)
                if tokens.count >= 3 {
                    let portSpec = tokens[2].split(separator: ":")
                    if portSpec.count == 2, let remotePort = Int(portSpec[1]) {
                        let resource = String(tokens[1])
                        return PortMappingInfo(localPort: port.port, remotePort: remotePort, remoteHost: resource, protocolName: port.protocolName)
                    }
                }
            }

        case .cloudflare:
            // Parse --url localhost:port or extract origin info
            if let range = full.range(of: #"--url\s+\S+:(\d+)"#, options: .regularExpression) {
                let match = String(full[range])
                let urlPart = match.split(separator: " ").last ?? ""
                let parts = urlPart.split(separator: ":")
                if let remotePort = Int(parts.last ?? "") {
                    return PortMappingInfo(localPort: port.port, remotePort: remotePort, remoteHost: "cloudflare", protocolName: port.protocolName)
                }
            }

        case .database:
            break
        case .local:
            break
        }

        return PortMappingInfo(localPort: port.port, remotePort: nil, remoteHost: nil, protocolName: port.protocolName)
    }

    private func parseSSHTunnelDetail(_ command: String) -> String? {
        // Match -L localPort:host:remotePort
        if let range = command.range(of: #"-[LR]\s+(\S+)"#, options: .regularExpression) {
            let match = String(command[range])
            // Remove the flag prefix (-L or -R + space)
            let spec = match.drop(while: { $0 != " " }).trimmingCharacters(in: .whitespaces)
            let parts = spec.split(separator: ":")
            if parts.count >= 3 {
                return "→ \(parts[1]):\(parts[2])"
            } else if parts.count == 2 {
                return "→ \(parts[0]):\(parts[1])"
            }
        }
        // Match -D port (SOCKS proxy)
        if let range = command.range(of: #"-D\s+(\d+)"#, options: .regularExpression) {
            let match = String(command[range])
            let proxyPort = match.split(separator: " ").last ?? ""
            return "SOCKS :\(proxyPort)"
        }
        return nil
    }

    private func parseKubectlTunnelDetail(_ command: String) -> String? {
        // Match port-forward (svc|pod|deploy)/name localPort:remotePort
        if let range = command.range(of: #"port-forward\s+(svc|pod|deploy|service|deployment)/(\S+)\s+(\d+:\d+)"#, options: .regularExpression) {
            let match = String(command[range])
            let parts = match.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 3 {
                let resource = parts[1]
                let ports = parts[2]
                return "\(resource):\(ports.split(separator: ":").last ?? ports)"
            }
        }
        return nil
    }

    private func parseCloudflareTunnelDetail(_ command: String) -> String? {
        // Match tunnel run <name>
        if let range = command.range(of: #"tunnel\s+run\s+(\S+)"#, options: .regularExpression) {
            let match = String(command[range])
            let name = match.split(separator: " ").last ?? ""
            return "tunnel: \(name)"
        }
        // Match access tcp
        if command.contains("access tcp") {
            return "access tcp"
        }
        return nil
    }

    // MARK: - Port Categorization

    private func categorizePort(_ port: PortProcess) -> PortCategory? {
        portManager.categorizePort(port.port)
    }

    func getCategory(for port: PortProcess) -> FilterCategory {
        if favorites.contains(port.port) { return .favorites }
        if let libCategory = categorizePort(port) {
            switch libCategory {
            case .web: return .web
            case .database: return .database
            case .dev: return .dev
            case .system: return .system
            case .custom: return .all
            }
        }
        if port.port < 1024 { return .system }
        return .all
    }

    func processType(for port: PortProcess) -> ProcessType {
        return ProcessClassifier.shared.classify(pid: port.pid)
    }

    /// I centralize source matching so the main window and menu bar stay consistent.
    func matchesSourceFilter(_ filter: PortSourceFilter, for port: PortProcess) -> Bool {
        switch filter {
        case .all:
            return true
        case .database:
            return connectionType(for: port) == .database || categorizePort(port) == .database
        case .orbstack:
            return isOrbStackPort(port)
        case .tunnels:
            let type = connectionType(for: port)
            return type == .ssh || type == .kubernetes || type == .cloudflare
        }
    }

    /// I detect OrbStack ports from process metadata without introducing more shell work.
    func isOrbStackPort(_ port: PortProcess) -> Bool {
        let searchableText = [
            port.command,
            port.fullCommand ?? "",
            port.processPath ?? "",
            port.workingDirectory ?? "",
            port.socketPath ?? ""
        ]
        .joined(separator: " ")
        .lowercased()

        return searchableText.contains("orbstack")
    }

    // MARK: - Refresh

    func refreshPorts() {
        isLoading = true
        dismissError()
        successMessage = nil

        let startPort = portRangeStart.isEmpty ? nil : Int(portRangeStart)
        let endPort = portRangeEnd.isEmpty ? nil : Int(portRangeEnd)

        // Validate port range
        if let start = startPort, start < 0 || start > 65535 {
            raiseError("Start port must be between 0 and 65535")
            isLoading = false
            return
        }
        if let end = endPort, end < 0 || end > 65535 {
            raiseError("End port must be between 0 and 65535")
            isLoading = false
            return
        }
        if let start = startPort, let end = endPort, start > end {
            raiseError("Start port cannot be greater than end port")
            isLoading = false
            return
        }

        let refreshID = UUID()
        latestRefreshID = refreshID

        let snapshotTask = Task.detached(priority: .userInitiated) {
            try Self.loadRefreshSnapshot(
                startPort: startPort,
                endPort: endPort
            )
        }

        Task {
            do {
                let snapshot = try await snapshotTask.value
                guard latestRefreshID == refreshID else { return }

                dockerInfoCache.removeAll()
                parentProcessNameCache = snapshot.parentProcessNames
                allPortsCache = snapshot.processes.sorted {
                    // I keep network ports ahead of sockets so the main list stays stable.
                    if $0.isUnixSocket != $1.isUnixSocket { return !$0.isUnixSocket }
                    if !$0.isUnixSocket { return $0.port < $1.port }
                    return $0.command < $1.command
                }
                ports = allPortsCache
                connectionTypeCache.removeAll()
                lastRefresh = Date()
                applyFilters()
                // Clear stale selection if the selected port no longer exists
                if let sel = selectedPort, !filteredPorts.contains(where: { $0.id == sel.id }) {
                    selectedPort = nil
                }
                isLoading = false
                addLog(
                    source: "system",
                    message: "Refreshed: \(snapshot.totalPorts) ports, \(snapshot.totalSockets) sockets",
                    level: .info
                )
            } catch {
                guard latestRefreshID == refreshID else { return }

                raiseError(error.localizedDescription)
                isLoading = false
                addLog(
                    source: "system",
                    message: "Refresh failed: \(error.localizedDescription)",
                    level: .error
                )
            }
        }
    }

    /// I keep shell and process discovery off the main actor and return one UI-ready snapshot.
    nonisolated private static func loadRefreshSnapshot(startPort: Int?, endPort: Int?) throws -> PortRefreshSnapshot {
        let portManager = PortManager()
        ProcessClassifier.shared.clearCache()

        var processes = try portManager.getListeningProcesses(
            startPort: startPort,
            endPort: endPort,
            protocolFilter: nil
        )

        // I only surface user-relevant Unix sockets in the app UI.
        let socketProcesses = portManager.getUnixSocketProcesses()
        let appSocketProcesses = socketProcesses.filter {
            ProcessClassifier.shared.classify(pid: $0.pid) != .system
        }
        processes.append(contentsOf: appSocketProcesses)

        let parentProcessNames = portManager.getParentProcessNames(
            forPIDs: processes.compactMap(\.parentPID)
        )

        return PortRefreshSnapshot(
            processes: processes,
            parentProcessNames: parentProcessNames,
            totalPorts: processes.filter { !$0.isUnixSocket }.count,
            totalSockets: appSocketProcesses.count
        )
    }

    // MARK: - Connections

    private var latestConnectionsRefreshID = UUID()

    func loadConnections(for port: Int) {
        isLoadingConnections = true
        connections = []

        // Task {} would inherit @MainActor and run the lsof shell-out on the
        // main thread — detached + static loader keeps the UI responsive.
        let refreshID = UUID()
        latestConnectionsRefreshID = refreshID
        let snapshotTask = Task.detached(priority: .userInitiated) {
            try Self.loadPortConnections(port: port)
        }

        Task {
            do {
                let conns = try await snapshotTask.value
                guard latestConnectionsRefreshID == refreshID else { return }
                connections = conns
            } catch {
                guard latestConnectionsRefreshID == refreshID else { return }
                // A failed lsof pass shouldn't read as "no connections" —
                // log it; the empty state stays honest.
                addLog(source: "system", message: "Connection load failed for port \(port): \(error.localizedDescription)", level: .error)
            }
            isLoadingConnections = false
        }
    }

    nonisolated private static func loadPortConnections(port: Int) throws -> [PortConnection] {
        try PortManager().getConnections(for: port)
    }

    // MARK: - All Connections (for menu bar Connections tab)

    /// Group all connections by process name for the Connections tab.
    /// Returns cached value to avoid repeated computation on each access.
    var connectionsGrouped: [(processName: String, connections: [EstablishedConnection], totalCount: Int)] {
        return connectionsGroupedCache
    }

    /// Refresh all established connections.
    func refreshAllConnections() {
        isLoadingAllConnections = true
        let refreshID = UUID()
        latestAllConnectionsRefreshID = refreshID

        let snapshotTask = Task.detached(priority: .userInitiated) {
            try Self.loadAllConnectionsSnapshot()
        }

        Task {
            do {
                let conns = try await snapshotTask.value
                guard latestAllConnectionsRefreshID == refreshID else { return }
                allConnections = conns
                updateConnectionsGroupedCache()
                isLoadingAllConnections = false
                checkConnectionAlerts()
            } catch {
                guard latestAllConnectionsRefreshID == refreshID else { return }
                // Keep the last good list — a failed lsof pass shouldn't
                // blank the whole Connections tab.
                updateConnectionsGroupedCache()
                isLoadingAllConnections = false
                addLog(source: "system", message: "Connection refresh failed: \(error.localizedDescription)", level: .error)
            }
        }
    }

    nonisolated private static func loadAllConnectionsSnapshot() throws -> [EstablishedConnection] {
        try PortManager().getAllConnections()
    }

    /// Check for suspicious connections and send notifications if needed
    private func checkConnectionAlerts() {
        guard hasAlert else { return }
        NotificationManager.shared.sendConnectionAlertNotification(
            blocklistedCount: blocklistedCount,
            suspiciousProcesses: suspiciousProcesses
        )
    }

    /// Update the cached grouped connections whenever allConnections changes.
    private func updateConnectionsGroupedCache() {
        let grouped = Dictionary(grouping: allConnections, by: { $0.processName })
        connectionsGroupedCache = grouped.map { (processName: $0.key, connections: $0.value, totalCount: $0.value.count) }
            .sorted { $0.totalCount > $1.totalCount }
    }

    private var latestCronjobsRefreshID = UUID()

    /// Refresh all cronjobs (scheduled tasks).
    func refreshCronjobs() {
        isLoadingCronjobs = true
        let refreshID = UUID()
        latestCronjobsRefreshID = refreshID

        let snapshotTask = Task.detached(priority: .userInitiated) {
            Self.loadCronjobsSnapshot()
        }

        Task {
            let jobs = await snapshotTask.value
            guard latestCronjobsRefreshID == refreshID else { return }
            cronjobs = jobs
            isLoadingCronjobs = false
            for job in jobs {
                cronRunHistory[job.id] = CronRunManager.shared.record(for: job.id)
            }
            runningCronjobIDs = Set(jobs.map(\.id).filter { CronRunManager.shared.isRunning($0) })
        }
    }

    nonisolated private static func loadCronjobsSnapshot() -> [CronjobEntry] {
        PortManager().getCronjobs()
    }

    // MARK: - Cronjob Control

    /// Wire up CronRunManager's callbacks so "Run Now" progress/results surface in the UI and Activity log.
    func setupCronRunCallbacks() {
        CronRunManager.shared.onUpdate = { [weak self] jobID, record in
            DispatchQueue.main.async {
                guard let self else { return }
                self.cronRunHistory[jobID] = record
                if record.isRunning {
                    self.runningCronjobIDs.insert(jobID)
                } else {
                    self.runningCronjobIDs.remove(jobID)
                }
            }
        }
        CronRunManager.shared.onLog = { [weak self] message, isError in
            DispatchQueue.main.async {
                self?.addLog(source: "cron", message: message, level: isError ? .error : .success)
            }
        }
    }

    /// Trigger a cronjob's command immediately, outside of its schedule.
    func runCronjobNow(_ job: CronjobEntry) {
        let started = CronRunManager.shared.runNow(job: job)
        if !started {
            addLog(source: "cron", message: "\(job.command) is already running", level: .info)
        }
    }

    /// Stop a cronjob run — whatever PortPilot started, plus a best-effort sweep for
    /// matching processes the cron daemon may have kicked off independently.
    func stopCronjob(_ job: CronjobEntry) {
        let command = job.command
        let jobID = job.id

        // Both kill paths walk process trees and TERM-wait — doing either on
        // the main actor hung the UI for up to ~3s per Stop click.
        let stopTask = Task.detached(priority: .userInitiated) {
            let stoppedTracked = CronRunManager.shared.stop(jobID: jobID)
            let killedCount = PortManager().stopRunningProcesses(matching: command)
            return (stoppedTracked, killedCount)
        }

        Task {
            let (stoppedTracked, killedCount) = await stopTask.value
            if stoppedTracked || killedCount > 0 {
                addLog(source: "cron", message: "Stopped \(command)", level: .info)
            } else {
                addLog(source: "cron", message: "\(command) is not currently running", level: .info)
            }
        }
    }

    /// Pause a user crontab entry so the cron daemon skips it until resumed.
    func pauseCronjob(_ job: CronjobEntry) {
        let command = job.command

        let pauseTask = Task.detached(priority: .userInitiated) {
            try PortManager().pauseCronjob(job)
        }

        Task {
            do {
                try await pauseTask.value
                addLog(source: "cron", message: "Paused \(command)", level: .info)
                refreshCronjobs()
            } catch {
                raiseError(error.localizedDescription)
                addLog(source: "cron", message: "Failed to pause \(command): \(error.localizedDescription)", level: .error)
            }
        }
    }

    /// Resume a paused user crontab entry.
    func resumeCronjob(_ job: CronjobEntry) {
        let command = job.command

        let resumeTask = Task.detached(priority: .userInitiated) {
            try PortManager().resumeCronjob(job)
        }

        Task {
            do {
                try await resumeTask.value
                addLog(source: "cron", message: "Started \(command)", level: .info)
                refreshCronjobs()
            } catch {
                raiseError(error.localizedDescription)
                addLog(source: "cron", message: "Failed to start \(command): \(error.localizedDescription)", level: .error)
            }
        }
    }

    /// Kill a process by PID (used from Connections tab).
    func killProcess(pid: Int) {
        let killTask = Task.detached(priority: .userInitiated) {
            try PortManager().killProcessByPID(pid)
        }

        Task {
            do {
                try await killTask.value
                addLog(source: "system", message: "Killed process \(pid)", level: .info)
                refreshAllConnections()
            } catch {
                addLog(source: "system", message: "Failed to kill process \(pid): \(error.localizedDescription)", level: .error)
            }
        }
    }

    // MARK: - Filtering

    func applyFilters() {
        var result = allPortsCache

        // Filter system processes if toggle is on
        if hideSystemProcesses {
            result = result.filter { !ProcessClassifier.shared.isSystemProcess(pid: $0.pid) }
        }

        if selectedProtocol != .all {
            result = result.filter { $0.protocolName.lowercased() == selectedProtocol.rawValue.lowercased() }
        }

        if selectedSourceFilter != .all {
            result = result.filter { matchesSourceFilter(selectedSourceFilter, for: $0) }
        }

        if selectedCategory == .favorites {
            result = result.filter { favorites.contains($0.port) }
        } else if selectedCategory != .all {
            let targetCategory: PortCategory
            switch selectedCategory {
            case .web: targetCategory = .web
            case .database: targetCategory = .database
            case .dev: targetCategory = .dev
            case .system: targetCategory = .system
            default: targetCategory = .custom
            }
            result = result.filter { categorizePort($0) == targetCategory }
        }

        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            result = result.filter {
                $0.command.lowercased().contains(searchLower) ||
                $0.user.lowercased().contains(searchLower) ||
                String($0.port).contains(searchLower) ||
                $0.protocolName.lowercased().contains(searchLower)
            }
        }

        filteredPorts = result
    }

    // MARK: - Kill Operations

    /// PID-direct kill from a row: the row showed this exact process, so
    /// that's what dies — not whatever grabbed the port between render and
    /// click.
    func killPort(_ port: PortProcess) {
        isLoading = true
        dismissError()
        successMessage = nil
        let force = forceKill
        let pid = port.pid

        let killTask = Task.detached(priority: .userInitiated) { () -> Bool in
            PortManager().killProcess(pids: [pid], force: force).isEmpty
        }

        Task {
            let killed = await killTask.value
            if killed {
                successMessage = "Killed \(port.command) on port \(port.port)"
                addLog(source: "kill", message: "Killed pid \(pid) (\(port.command)) on port \(port.port)", level: .success, port: port.port)
            } else {
                raiseError("Failed to kill \(port.command) (pid \(pid))")
                isLoading = false
                addLog(source: "kill", message: "Failed to kill pid \(pid) on port \(port.port)", level: .error, port: port.port)
            }
            refreshPorts()
        }
    }

    func killSelectedPorts(_ selectedPorts: Set<PortProcess>) {
        isLoading = true
        dismissError()
        let force = forceKill
        // PID-direct: kill exactly what was selected. Re-resolving by port
        // mid-loop could sweep in processes that started after the selection.
        let targets = selectedPorts.map { (port: $0.port, pid: $0.pid) }

        let killTask = Task.detached(priority: .userInitiated) { () -> [(port: Int, pid: Int)] in
            let manager = PortManager()
            var failed: [(port: Int, pid: Int)] = []
            for target in targets {
                let survivors = manager.killProcess(pids: [target.pid], force: force)
                if !survivors.isEmpty {
                    failed.append(target)
                }
            }
            return failed
        }

        Task {
            let failures = await killTask.value
            // One aggregated message — the loop used to overwrite the error
            // each turn, so only the last failure ever reached the user.
            if !failures.isEmpty {
                let detail = failures
                    .map { ":\($0.port) (pid \($0.pid))" }
                    .joined(separator: ", ")
                raiseError("Failed to kill \(failures.count) of \(targets.count): \(detail)")
            }
            for failure in failures {
                addLog(source: "kill", message: "Failed to kill port \(failure.port): pid \(failure.pid) survived", level: .error, port: failure.port)
            }
            let killedCount = targets.count - failures.count
            if killedCount > 0 {
                successMessage = "Killed \(killedCount) port(s)"
                addLog(source: "kill", message: "Killed \(killedCount) process(es)", level: .success)
            }
            refreshPorts()
        }
    }

    func clearFilters() {
        portRangeStart = ""
        portRangeEnd = ""
        selectedProtocol = .tcp
        searchText = ""
        selectedCategory = .all
        selectedSourceFilter = .all
        hideSystemProcesses = false
        applyFilters()
    }

    // MARK: - Favorites

    func isFavorite(port: Int) -> Bool {
        favorites.contains(port)
    }

    func toggleFavorite(port: Int) {
        if favorites.contains(port) {
            favorites.remove(port)
        } else {
            favorites.insert(port)
        }
        saveFavorites()
        applyFilters()
    }

    private func loadFavorites() {
        let defaults = UserDefaults.standard
        let array = defaults.array(forKey: "FavoritePorts") as? [Int] ?? []
        favorites = Set(array)
    }

    private func saveFavorites() {
        let defaults = UserDefaults.standard
        defaults.set(Array(favorites), forKey: "FavoritePorts")
    }

    // MARK: - Connection Names

    private static let connectionNamesKey = "ConnectionNames"

    func connectionNameKey(port: Int, protocol proto: String) -> String {
        "\(port):\(proto.lowercased())"
    }

    func connectionName(for port: PortProcess) -> String? {
        let key = connectionNameKey(port: port.port, protocol: port.protocolName)
        return connectionNames[key]
    }

    func setConnectionName(port: Int, protocol proto: String, name: String) {
        let key = connectionNameKey(port: port, protocol: proto)
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            connectionNames.removeValue(forKey: key)
        } else {
            connectionNames[key] = name
        }
        saveConnectionNames()
    }

    private func loadConnectionNames() {
        let defaults = UserDefaults.standard
        connectionNames = defaults.dictionary(forKey: Self.connectionNamesKey) as? [String: String] ?? [:]
    }

    private func saveConnectionNames() {
        let defaults = UserDefaults.standard
        defaults.set(connectionNames, forKey: Self.connectionNamesKey)
    }

    // MARK: - Copy Info

    func copyPortInfo(_ port: PortProcess) {
        let info = """
        Port: \(port.port)
        Protocol: \(port.protocolName.uppercased())
        PID: \(port.pid)
        User: \(port.user)
        Command: \(port.command)
        """

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(info, forType: .string)
    }

    // MARK: - Log Management

    func addLog(source: String, message: String, level: LogEntry.LogLevel, port: Int? = nil) {
        let entry = LogEntry(timestamp: Date(), source: source, message: message, level: level, portNumber: port)
        logs.append(entry)

        // Keep last 500 entries
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
    }

    func logsForPort(_ port: Int) -> [LogEntry] {
        logs.filter { $0.portNumber == port || $0.portNumber == nil }
    }

    func clearLogs() {
        logs.removeAll()
    }

    func copyLogs() {
        let text = logs.map { "\($0.formattedTime) [\($0.source)] \($0.message)" }.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Process Intelligence

    /// Returns a human-readable uptime string like "2h 30m" or "3d 4h"
    func processUptime(for port: PortProcess) -> String? {
        guard let startTime = port.startTime else { return nil }
        let interval = Date().timeIntervalSince(startTime)
        guard interval >= 0 else { return nil }

        let secondsInMinute: Double = 60
        let secondsInHour: Double = 3600
        let secondsInDay: Double = 86400

        let days = Int(interval / secondsInDay)
        let hours = Int((interval.truncatingRemainder(dividingBy: secondsInDay)) / secondsInHour)
        let minutes = Int((interval.truncatingRemainder(dividingBy: secondsInHour)) / secondsInMinute)
        let seconds = Int(interval.truncatingRemainder(dividingBy: secondsInMinute))

        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(seconds)s"
        }
    }

    /// Returns the parent process name for a given port process.
    /// Results are cached per PID within the session.
    /// Returns nil if not cached - use this only for display after data is loaded.
    func parentProcessName(for port: PortProcess) -> String? {
        guard let ppid = port.parentPID else { return nil }
        // Only return cached values - don't call runCommand during view rendering
        return parentProcessNameCache[ppid]
    }

    // MARK: - Docker Integration

    /// Container details for a port backed by a Docker container (Port Mapping panel).

    /// Known Docker-related process names
    private static let dockerProcessNames: Set<String> = [
        "docker", "dockerd", "containerd", "docker-compose",
        "com.docker.hyperkit", "com.docker.vpnkit", "docker-proxy"
    ]
    // Docker info cache to avoid blocking calls during rendering
    // Keyed by PID since a Docker container/process may expose multiple ports
    private var dockerInfoCache: [Int: DockerInfo?] = [:]
    /// PIDs with a docker lookup already in flight, so body re-evaluations
    /// don't fan out one `docker ps` per render.
    private var dockerLookupsInFlight: Set<Int> = []

    /// Returns cached Docker container info. Never blocks - returns nil if not cached yet.
    func dockerInfo(for port: PortProcess) -> DockerInfo? {
        let command = port.command.lowercased()

        let isDockerRelated = Self.dockerProcessNames.contains(command) ||
                            command.contains("docker") ||
                            command.contains("containerd")

        guard isDockerRelated else { return nil }

        // Return cached value if available (keyed by PID for correctness)
        if let cached = dockerInfoCache[port.pid] {
            return cached
        }
        guard !dockerLookupsInFlight.contains(port.pid) else { return nil }
        dockerLookupsInFlight.insert(port.pid)

        // Fetch asynchronously - don't block the main thread
        let portNum = port.port
        let pid = port.pid
        Task.detached(priority: .utility) { [weak self] in
            let containerInfo = PortManager.getContainerInfo(forPort: portNum)
            await MainActor.run {
                guard let self = self else { return }
                self.dockerLookupsInFlight.remove(pid)
                self.dockerInfoCache[pid] = containerInfo
                self.objectWillChange.send()
            }
        }
        return nil
    }

    /// Check if a port is running inside a Docker container
    func isDockerContainer(for port: PortProcess) -> Bool {
        let command = port.command.lowercased()
        return Self.dockerProcessNames.contains(command) ||
               command.contains("docker") ||
               command.contains("containerd")
    }

    /// Stop a Docker container off the main thread, then refresh so the UI
    /// reflects the new container state instead of a stale cache entry.
    func stopContainer(_ containerId: String) {
        let task = Task.detached(priority: .userInitiated) {
            PortManager.dockerRunQuiet(["stop", containerId], timeout: 30)
        }
        Task {
            let ok = await task.value
            if !ok {
                raiseError("Failed to stop container \(containerId.prefix(12)) — is Docker running?")
            }
            addLog(source: "docker", message: ok ? "Stopped container \(containerId.prefix(12))" : "Failed to stop container \(containerId.prefix(12))", level: ok ? .info : .error)
            refreshPorts()
        }
    }

    /// Restart a Docker container off the main thread, then refresh.
    func restartContainer(_ containerId: String) {
        let task = Task.detached(priority: .userInitiated) {
            PortManager.dockerRunQuiet(["restart", containerId], timeout: 60)
        }
        Task {
            let ok = await task.value
            if !ok {
                raiseError("Failed to restart container \(containerId.prefix(12)) — is Docker running?")
            }
            addLog(source: "docker", message: ok ? "Restarted container \(containerId.prefix(12))" : "Failed to restart container \(containerId.prefix(12))", level: ok ? .info : .error)
            refreshPorts()
        }
    }

    // MARK: - Reserved Ports

    func isReserved(port: Int) -> Bool {
        AppSettings.shared.reservedPorts.contains(port)
    }

    func checkReservedPorts() -> [(port: Int, occupant: String)] {
        var threatened: [(port: Int, occupant: String)] = []
        let reserved = AppSettings.shared.reservedPorts

        for port in reserved {
            if let process = allPortsCache.first(where: { $0.port == port }) {
                threatened.append((port: port, occupant: "\(process.command) (PID: \(process.pid))"))
            }
        }

        return threatened
    }

    func addReservedPort(_ port: Int) {
        if !AppSettings.shared.reservedPorts.contains(port) && port > 0 && port <= 65535 {
            AppSettings.shared.reservedPorts.append(port)
            AppSettings.shared.reservedPorts.sort()
        }
    }

    func removeReservedPort(_ port: Int) {
        AppSettings.shared.reservedPorts.removeAll { $0 == port }
    }

    // MARK: - Proxy Management

    func startProxy(listenPort: Int, targetHost: String, targetPort: Int) {
        do {
            let session = try TCPProxyManager.shared.startProxy(
                listenPort: listenPort,
                targetHost: targetHost,
                targetPort: targetPort
            )
            proxySessions.append(session)
            addLog(source: "proxy", message: "Started proxy :\(listenPort) \u{2192} \(targetHost):\(targetPort)", level: .success, port: listenPort)
        } catch {
            raiseError(error.localizedDescription)
            addLog(source: "proxy", message: "Failed to start proxy: \(error.localizedDescription)", level: .error)
        }
    }

    func stopProxy(id: UUID) {
        TCPProxyManager.shared.stopProxy(id: id)
        proxySessions.removeAll { $0.id == id }
        addLog(source: "proxy", message: "Stopped proxy session", level: .info)
    }

    func stopAllProxies() {
        TCPProxyManager.shared.stopAll()
        proxySessions.removeAll()
        addLog(source: "proxy", message: "Stopped all proxy sessions", level: .info)
    }

    func setupProxyCallbacks() {
        TCPProxyManager.shared.onSessionUpdated = { [weak self] session in
            DispatchQueue.main.async {
                if let index = self?.proxySessions.firstIndex(where: { $0.id == session.id }) {
                    self?.proxySessions[index] = session
                }
            }
        }
        TCPProxyManager.shared.onLog = { [weak self] message in
            DispatchQueue.main.async {
                self?.addLog(source: "proxy", message: message, level: .info)
            }
        }
        TCPProxyManager.shared.onError = { [weak self] _, error in
            DispatchQueue.main.async {
                self?.addLog(source: "proxy", message: error, level: .error)
            }
        }
    }
}

// MARK: - PortViewModel Extension for hasActiveFilters
extension PortViewModel {
    var hasActiveFilters: Bool {
        // selectedSourceFilter and hideSystemProcesses used to be missing
        // here — filtering to "Tunnels" with no hits claimed "No ports found"
        // with no Clear button, and hideSystemProcesses alone showed a Clear
        // button that cleared nothing.
        !searchText.isEmpty || selectedCategory != .all || selectedProtocol != .all
            || selectedSourceFilter != .all || hideSystemProcesses
    }
}

// MARK: - Alert Detection
extension PortViewModel {
    /// Count of blocklisted connections
    var blocklistedCount: Int {
        allConnections.filter { $0.isBlocklisted }.count
    }

    /// Count of suspicious processes (more than 50 connections)
    var suspiciousConnectionCount: Int {
        connectionsGrouped.filter { $0.totalCount > 50 }.count
    }

    /// Whether any alert condition exists
    var hasAlert: Bool {
        blocklistedCount > 0 || suspiciousConnectionCount > 0
    }

    /// Combined alert count
    var alertCount: Int {
        blocklistedCount + suspiciousConnectionCount
    }

    /// List of suspicious processes with their connection counts
    var suspiciousProcesses: [(processName: String, connectionCount: Int)] {
        connectionsGrouped
            .filter { $0.totalCount > 50 }
            .map { (processName: $0.processName, connectionCount: $0.totalCount) }
    }

    /// Alert state for UI display
    var alertState: AlertState {
        if blocklistedCount > 0 { return .critical }
        if suspiciousConnectionCount > 0 { return .warning }
        return .normal
    }
}
