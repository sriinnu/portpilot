import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Classification of a process based on its executable path and ownership
public enum ProcessType: String, Codable, CaseIterable {
    case system = "System"
    case userApp = "App"
    case developerTool = "Developer"
    case other = "Other"

    public var icon: String {
        switch self {
        case .system: return "gearshape.2.fill"
        case .userApp: return "app.fill"
        case .developerTool: return "hammer.fill"
        case .other: return "questionmark.circle"
        }
    }
}

public final class ProcessClassifier {
    public static let shared = ProcessClassifier()

    private var cache: [Int: ProcessType] = [:]
    private let lock = NSLock()

    public init() {}

    /// Get the executable path for a PID using proc_pidpath
    public func getProcessPath(pid: Int) -> String? {
        #if os(macOS)
        let pathBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(MAXPATHLEN))
        defer { pathBuffer.deallocate() }
        let pathLength = proc_pidpath(Int32(pid), pathBuffer, UInt32(MAXPATHLEN))
        guard pathLength > 0 else { return nil }
        return String(cString: pathBuffer)
        #else
        // Linux: read /proc/pid/exe
        return try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/\(pid)/exe")
        #endif
    }

    /// Classify a process by its PID, with caching
    public func classify(pid: Int) -> ProcessType {
        lock.lock()
        if let cached = cache[pid] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let path = getProcessPath(pid: pid) else {
            let result = ProcessType.other
            lock.lock()
            cache[pid] = result
            lock.unlock()
            return result
        }

        let result = classifyByPath(path)
        lock.lock()
        cache[pid] = result
        lock.unlock()
        return result
    }

    /// Classify based on executable path heuristics
    public func classifyByPath(_ path: String) -> ProcessType {
        // System processes: Apple system locations
        let systemPrefixes = [
            "/System/",
            "/usr/libexec/",
            "/usr/sbin/",
            "/sbin/",
            "/Library/Apple/",
            "/usr/bin/",
        ]

        // Known system commands that live in /usr/bin but are OS-level
        let systemCommands: Set<String> = [
            "mDNSResponder", "launchd", "WindowServer", "loginwindow",
            "SystemUIServer", "Dock", "Finder", "AirPlayXPCHelper",
            "airportd", "bluetoothd", "configd", "coreaudiod",
            "corebrightnessd", "diskarbitrationd", "fseventsd",
            "hidd", "iconservicesagent", "kernelmanagerd",
            "logd", "notifyd", "opendirectoryd", "powerd",
            "rapportd", "sharingd", "syslogd", "thermald",
            "trustd", "usbd", "UserEventAgent", "warmd",
            "wifid", "backupd", "bird", "cloudd",
            "CommCenter", "cfprefsd", "coreservicesd", "distnoted",
            "filecoordinationd", "fontd", "lsd", "mediaremoted",
            "nsurlsessiond", "pboard", "secd", "securityd",
            "symptomsd", "tccd", "timed", "watchdogd"
        ]

        let basename = (path as NSString).lastPathComponent

        // Check known system commands
        if systemCommands.contains(basename) {
            return .system
        }

        // Check system path prefixes
        for prefix in systemPrefixes {
            if path.hasPrefix(prefix) {
                return .system
            }
        }

        // Developer tools installed via Homebrew or similar
        let devPrefixes = [
            "/opt/homebrew/",
            "/usr/local/bin/",
            "/usr/local/opt/",
            "/usr/local/Cellar/",
        ]

        let devCommands: Set<String> = [
            "node", "python3", "python", "ruby", "java", "go",
            "cargo", "rustc", "deno", "bun", "npm", "yarn", "pnpm",
            "php", "perl", "nginx", "httpd", "caddy", "traefik",
            "docker", "dockerd", "containerd", "kubectl", "helm",
            "postgres", "postmaster", "mysqld", "mongod", "redis-server",
            "redis-sentinel", "memcached", "influxd", "clickhouse-server",
            "elasticsearch", "kibana", "grafana-server", "prometheus",
            "code", "electron", "webpack", "vite", "esbuild",
            "ssh", "cloudflared", "ngrok", "localtunnel",
            "pgbouncer", "haproxy", "envoy", "consul",
        ]

        if devCommands.contains(basename) {
            return .developerTool
        }

        for prefix in devPrefixes {
            if path.hasPrefix(prefix) {
                return .developerTool
            }
        }

        // User applications: .app bundles or /Applications
        if path.contains(".app/") || path.hasPrefix("/Applications/") {
            return .userApp
        }

        // User home directory apps
        if path.hasPrefix(NSHomeDirectory()) {
            return .userApp
        }

        return .other
    }

    /// Clear the cache (e.g., on refresh)
    public func clearCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    /// Check if a process should be considered "system" (hidden by default filter)
    public func isSystemProcess(pid: Int) -> Bool {
        classify(pid: pid) == .system
    }
}
