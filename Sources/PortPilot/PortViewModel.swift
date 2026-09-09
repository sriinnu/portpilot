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

    // Cronjobs (for Schedules tab) — owned by the controller; these
    // forwards keep view call sites stable. The VM relays the controller's
    // objectWillChange so views observing the VM stay live.
    let cron: CronjobController
    var cronjobs: [CronjobEntry] { cron.jobs }
    var isLoadingCronjobs: Bool { cron.isLoading }
    var cronRunHistory: [String: CronRunRecord] { cron.runHistory }
    var runningCronjobIDs: Set<String> { cron.runningIDs }

    // Port guard — armed enforcement, independent of the monitoring toggle.
    let portGuard: PortGuardStore
    func isGuarded(_ port: Int) -> Bool { portGuard.isGuarded(port) }

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

    // Logs — owned by the activity store; `logs` forwards for existing call sites.
    let activityLog = ActivityLogStore()
    var logs: [LogEntry] { activityLog.entries }

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

    private var cancellables: Set<AnyCancellable> = []

    init() {
        // First: cron and portGuard have no defaults, and their error hooks
        // capture self — assign before anything else uses self.
        cron = CronjobController(log: activityLog)
        portGuard = PortGuardStore(log: activityLog)
        cron.onError = { [weak self] message in self?.raiseError(message) }
        portGuard.onError = { [weak self] message in self?.raiseError(message) }

        // One central relay: store mutations re-render views that observe
        // the VM, so no view has to observe the stores directly.
        activityLog.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        cron.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        portGuard.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        loadFavorites()
        loadConnectionNames()
        refreshPorts()
        setupProxyCallbacks()
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

    func connectionType(for port: PortProcess) -> ConnectionType {
        // Scans fullCommand with a dozen contains() per call — and rows call
        // it twice per render (icon + color). Cached per data snapshot.
        if let cached = connectionTypeCache[port.id] {
            return cached
        }
        let resolved = TunnelInspector.resolveConnectionType(for: port)
        connectionTypeCache[port.id] = resolved
        return resolved
    }

    func tunnelName(for port: PortProcess) -> String? { TunnelInspector.tunnelName(for: port) }
    func tunnelDetail(for port: PortProcess) -> String? { TunnelInspector.tunnelDetail(for: port) }
    func kubeNamespace(for port: PortProcess) -> String { TunnelInspector.kubeNamespace(for: port) }
    func portMappingInfo(for port: PortProcess) -> PortMappingInfo { TunnelInspector.portMappingInfo(for: port) }

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
                let previousPorts = allPortsCache
                allPortsCache = snapshot.processes.sorted {
                    // I keep network ports ahead of sockets so the main list stays stable.
                    if $0.isUnixSocket != $1.isUnixSocket { return !$0.isUnixSocket }
                    if !$0.isUnixSocket { return $0.port < $1.port }
                    return $0.command < $1.command
                }
                ports = allPortsCache
                connectionTypeCache.removeAll()
                lastRefresh = Date()
                // Only full scans feed the timeline — a ranged refresh would
                // read as mass frees (everything outside the range), then a
                // storm of binds when the range clears.
                if startPort == nil && endPort == nil {
                    emitTimelineEvents(previous: previousPorts, current: allPortsCache)
                }
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

    /// Timeline: flips after the first snapshot lands so the initial
    /// population doesn't fire a storm of "bound" events.
    private var hasPortBaseline = false

    /// Diff two port snapshots into timeline events. Network ports only —
    /// Unix sockets churn constantly and would bury the signal.
    private func emitTimelineEvents(previous: [PortProcess], current: [PortProcess]) {
        guard hasPortBaseline else {
            hasPortBaseline = true
            return
        }

        let previousKeys = Set(previous.filter { !$0.isUnixSocket }.map(Self.timelineKey))
        let currentKeys = Set(current.filter { !$0.isUnixSocket }.map(Self.timelineKey))

        for process in current where !process.isUnixSocket {
            if !previousKeys.contains(Self.timelineKey(process)) {
                addLog(
                    source: "timeline",
                    message: "\(process.command) bound :\(process.port)",
                    level: .success,
                    port: process.port,
                    event: .bound
                )
            }
        }
        for process in previous where !process.isUnixSocket {
            if !currentKeys.contains(Self.timelineKey(process)) {
                addLog(
                    source: "timeline",
                    message: "\(process.command) released :\(process.port)",
                    level: .info,
                    port: process.port,
                    event: .freed
                )
            }
        }
    }

    /// A process instance on the wire: same port held by a new pid is a
    /// release + a bind, which is exactly the story the timeline should tell.
    private static func timelineKey(_ process: PortProcess) -> String {
        "\(process.port):\(process.protocolName):\(process.pid)"
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

    // MARK: - Cronjob Control

    func refreshCronjobs() { cron.refresh() }
    func runCronjobNow(_ job: CronjobEntry) { cron.runNow(job) }
    func stopCronjob(_ job: CronjobEntry) { cron.stop(job) }
    func pauseCronjob(_ job: CronjobEntry) { cron.pause(job) }
    func resumeCronjob(_ job: CronjobEntry) { cron.resume(job) }

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
                addLog(source: "kill", message: "Killed pid \(pid) (\(port.command)) on port \(port.port)", level: .success, port: port.port, event: .killed)
            } else {
                raiseError("Failed to kill \(port.command) (pid \(pid))")
                isLoading = false
                addLog(source: "kill", message: "Failed to kill pid \(pid) on port \(port.port)", level: .error, port: port.port)
            }
            refreshPorts()
        }
    }

    // MARK: - Pause / Resume Operations

    /// SIGSTOP the row's exact pid. Reversible — no confirmation needed.
    /// The socket stays bound; the process freezes with full state.
    func pauseProcess(_ process: PortProcess) {
        signalProcess(process, signal: "pause") {
            !PortManager().pauseProcess(pids: [$0]).isEmpty
        }
    }

    /// SIGCONT a frozen process — it resumes where it stopped.
    func resumeProcess(_ process: PortProcess) {
        signalProcess(process, signal: "resume") {
            !PortManager().resumeProcess(pids: [$0]).isEmpty
        }
    }

    private func signalProcess(_ process: PortProcess, signal: String, deliver: @escaping (Int) -> Bool) {
        dismissError()
        successMessage = nil
        let pid = process.pid

        let signalTask = Task.detached(priority: .userInitiated) { () -> Bool in
            deliver(pid)
        }

        Task {
            let delivered = await signalTask.value
            if delivered {
                let verb = signal == "pause" ? "Paused" : "Resumed"
                successMessage = "\(verb) \(process.command) on port \(process.port)"
                addLog(source: signal, message: "\(verb) pid \(pid) (\(process.command)) on port \(process.port)", level: .success, port: process.port, event: signal == "pause" ? .paused : .resumed)
            } else {
                raiseError("Failed to \(signal) \(process.command) (pid \(pid))")
                addLog(source: signal, message: "Failed to \(signal) pid \(pid) on port \(process.port)", level: .error, port: process.port)
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
                addLog(source: "kill", message: "Killed \(killedCount) process(es)", level: .success, event: .killed)
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

    func addLog(source: String, message: String, level: LogEntry.LogLevel, port: Int? = nil, event: LogEntry.LogEvent? = nil) {
        activityLog.add(source: source, message: message, level: level, port: port, event: event)
    }

    func logsForPort(_ port: Int) -> [LogEntry] {
        activityLog.entries(for: port)
    }

    func clearLogs() {
        activityLog.clear()
    }

    func copyLogs() {
        activityLog.copyAll()
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
    /// True while any known port process is SIGSTOPped — the menubar icon
    /// switches to a paused glyph so a frozen server isn't forgotten.
    var hasFrozenProcess: Bool {
        allPortsCache.contains { $0.isStopped }
    }

    /// Bound/released events since `date` — the menubar's "changed since
    /// you last looked" count. Resets when the dropdown opens.
    func timelineChangeCount(since date: Date) -> Int {
        activityLog.entries.filter { entry in
            guard let event = entry.event, entry.timestamp > date else { return false }
            return event == .bound || event == .freed
        }.count
    }

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
