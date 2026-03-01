import Foundation
import Combine
import PortManagerLib
import AppKit
import SwiftUI

// MARK: - Connection Type
enum ConnectionType: String, CaseIterable, Identifiable {
    case local = "Local"
    case kubernetes = "Kubernetes"
    case cloudflare = "Cloudflare"
    case ssh = "SSH"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .local: return Theme.Icon.local
        case .kubernetes: return Theme.Icon.kubernetes
        case .cloudflare: return Theme.Icon.cloudflare
        case .ssh: return Theme.Icon.ssh
        }
    }

    var color: Color {
        switch self {
        case .local: return Theme.Section.local
        case .kubernetes: return Theme.Section.kubernetes
        case .cloudflare: return Theme.Section.cloudflare
        case .ssh: return Theme.Section.ssh
        }
    }
}

// MARK: - Port Forward Model
struct PortForward: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let type: ConnectionType
    let localPort: Int
    let remotePort: Int?
    let isConnected: Bool
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

// MARK: - Port Mapping Info
struct PortMappingInfo {
    let localPort: Int
    let remotePort: Int?
    let remoteHost: String?
    let protocolName: String
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
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var lastRefresh: Date?

    // Logs
    @Published var logs: [LogEntry] = []

    // Port forwards (all local for now)
    @Published var portForwards: [PortForward] = []

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

    private let portManager = PortManager()
    private var allPortsCache: [PortProcess] = []

    @Published private(set) var favorites: Set<Int> = []
    @Published private(set) var connectionNames: [String: String] = [:]

    enum ProtocolFilter: String, CaseIterable {
        case tcp = "TCP"
        case udp = "UDP"
        case all = "All"
    }

    init() {
        loadFavorites()
        loadConnectionNames()
        refreshPorts()
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

    // MARK: - Port Grouping

    /// Group ports by connection type based on process and full command.
    var groupedPorts: [ConnectionType: [PortProcess]] {
        Dictionary(grouping: filteredPorts) { connectionType(for: $0) }
    }

    // MARK: - Tunnel Detection

    func connectionType(for port: PortProcess) -> ConnectionType {
        let basename = port.command.lowercased()
        let full = (port.fullCommand ?? "").lowercased()

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

    // MARK: - Refresh

    func refreshPorts() {
        isLoading = true
        errorMessage = nil
        successMessage = nil

        Task {
            do {
                let startPort = portRangeStart.isEmpty ? nil : Int(portRangeStart)
                let endPort = portRangeEnd.isEmpty ? nil : Int(portRangeEnd)

                let processes = try portManager.getListeningProcesses(
                    startPort: startPort,
                    endPort: endPort,
                    protocolFilter: nil
                )

                await MainActor.run {
                    self.allPortsCache = processes.sorted { $0.port < $1.port }
                    self.ports = self.allPortsCache
                    self.lastRefresh = Date()
                    self.applyFilters()
                    self.isLoading = false
                    self.addLog(source: "system", message: "Refreshed: found \(processes.count) ports", level: .info)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    self.addLog(source: "system", message: "Refresh failed: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }

    // MARK: - Connections

    func loadConnections(for port: Int) {
        isLoadingConnections = true
        connections = []

        Task {
            do {
                let portConnections = try portManager.getConnections(for: port)
                await MainActor.run {
                    self.connections = portConnections
                    self.isLoadingConnections = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingConnections = false
                }
            }
        }
    }

    // MARK: - Filtering

    func applyFilters() {
        var result = allPortsCache

        if selectedProtocol != .all {
            result = result.filter { $0.protocolName.lowercased() == selectedProtocol.rawValue.lowercased() }
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

    func killPort(_ port: Int) {
        isLoading = true
        errorMessage = nil
        successMessage = nil

        Task {
            do {
                try portManager.killProcessOnPort(port, force: forceKill)

                await MainActor.run {
                    self.successMessage = "Successfully killed process on port \(port)"
                    self.addLog(source: "kill", message: "Killed process on port \(port)", level: .success, port: port)
                    self.refreshPorts()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    self.addLog(source: "kill", message: "Failed to kill port \(port): \(error.localizedDescription)", level: .error, port: port)
                }
            }
        }
    }

    func killSelectedPorts(_ selectedPorts: Set<PortProcess>) {
        isLoading = true
        errorMessage = nil

        Task {
            for process in selectedPorts {
                do {
                    try portManager.killProcessOnPort(process.port, force: forceKill)
                    await MainActor.run {
                        self.addLog(source: "kill", message: "Killed process on port \(process.port)", level: .success, port: process.port)
                    }
                } catch {
                    await MainActor.run {
                        self.errorMessage = "Failed to kill port \(process.port): \(error.localizedDescription)"
                        self.addLog(source: "kill", message: "Failed to kill port \(process.port): \(error.localizedDescription)", level: .error, port: process.port)
                    }
                }
            }

            await MainActor.run {
                self.successMessage = "Killed \(selectedPorts.count) port(s)"
                self.refreshPorts()
            }
        }
    }

    func clearFilters() {
        portRangeStart = ""
        portRangeEnd = ""
        selectedProtocol = .tcp
        searchText = ""
        selectedCategory = .all
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
}

// MARK: - PortViewModel Extension for hasActiveFilters
extension PortViewModel {
    var hasActiveFilters: Bool {
        !searchText.isEmpty || selectedCategory != .all || selectedProtocol != .all
    }
}
