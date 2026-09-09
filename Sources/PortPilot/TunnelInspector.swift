import Foundation

/// Tunnel and connection-type classification — pure functions over an
/// immutable PortProcess snapshot. Pulled out of PortViewModel unchanged;
/// the VM keeps only the per-snapshot cache that dedupes these calls.
enum TunnelInspector {
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

    static func resolveConnectionType(for port: PortProcess) -> ConnectionType {
        let basename = port.command.lowercased()
        let full = (port.fullCommand ?? "").lowercased()

        // Check for database processes first
        if databaseProcesses.contains(basename) {
            return .database
        }

        // Check full command for database patterns
        for dbProcess in databaseProcesses {
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

    static func tunnelName(for port: PortProcess) -> String? {
        guard let full = port.fullCommand else { return nil }
        let type = resolveConnectionType(for: port)

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
                return match.split(separator: " ").last.map(String.init)
            }
            // Extract hostname: --hostname <host>
            if let range = full.range(of: #"--hostname\s+(\S+)"#, options: .regularExpression) {
                let match = String(full[range])
                return match.split(separator: " ").last.map(String.init)
            }
            return nil

        case .database:
            return nil
        case .local:
            return nil
        }
    }

    static func tunnelDetail(for port: PortProcess) -> String? {
        guard let full = port.fullCommand else { return nil }
        let type = resolveConnectionType(for: port)

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

    static func kubeNamespace(for port: PortProcess) -> String {
        guard let full = port.fullCommand else { return "default" }
        let tokens = full.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        for (i, token) in tokens.enumerated() {
            if (token == "-n" || token == "--namespace") && i + 1 < tokens.count {
                return tokens[i + 1]
            }
        }
        return "default"
    }

    static func portMappingInfo(for port: PortProcess) -> PortMappingInfo {
        guard let full = port.fullCommand else {
            return PortMappingInfo(localPort: port.port, remotePort: nil, remoteHost: nil, protocolName: port.protocolName)
        }
        let type = resolveConnectionType(for: port)

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

    // MARK: - Detail Parsers

    private static func parseSSHTunnelDetail(_ command: String) -> String? {
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

    private static func parseKubectlTunnelDetail(_ command: String) -> String? {
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

    private static func parseCloudflareTunnelDetail(_ command: String) -> String? {
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
}
