import Foundation
import ArgumentParser
import PortManagerLib

// MARK: - Command Types (defined first for subcommands reference)

// MARK: - List Command
extension PortKiller {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all processes listening on ports"
        )

        @Option(name: .shortAndLong, help: "Start of port range")
        var start: Int?

        @Option(name: .shortAndLong, help: "End of port range")
        var end: Int?

        @Option(name: .shortAndLong, help: "Filter by protocol (tcp/udp)")
        var proto: String?

        @Flag(name: .long, help: "Output in JSON format")
        var json: Bool = false

        func run() throws {
            let portManager = PortManager()
            let processes = try portManager.getListeningProcesses(
                startPort: start,
                endPort: end,
                protocolFilter: proto
            )

            if json {
                try outputJSON(processes)
            } else {
                outputTable(processes)
            }
        }

        private func outputTable(_ processes: [PortProcess]) {
            if processes.isEmpty {
                print("No processes found listening on the specified ports.")
                return
            }

            print("\n🔍 Listening Processes:")
            print(String(repeating: "─", count: 98))
            print(headerRow())
            print(String(repeating: "─", count: 98))

            for process in processes.sorted(by: { $0.port < $1.port }) {
                print(row(process))
            }
            print(String(repeating: "─", count: 98))
            print("\nFound \(processes.count) process(es)")
        }

        private func headerRow() -> String {
            let port = "PORT".padRight(width: 8)
            let proto = "PROTO".padRight(width: 6)
            let pid = "PID".padRight(width: 8)
            let cpu = "CPU%".padRight(width: 8)
            let mem = "MEM".padRight(width: 8)
            let user = "USER".padRight(width: 12)
            let command = "COMMAND".padRight(width: 18)
            return "\(port) \(proto) \(pid) \(cpu) \(mem) \(user) \(command) PATH/PROJECT"
        }

        private func row(_ process: PortProcess) -> String {
            let port = "\(process.port)".padRight(width: 8)
            let proto = process.protocolName.uppercased().padRight(width: 6)
            let pid = "\(process.pid)".padRight(width: 8)
            let cpu = (process.cpuUsage.map { String(format: "%.1f", $0) } ?? "-").padRight(width: 8)
            let mem = (process.memoryMB.map { formatMem($0) } ?? "-").padRight(width: 8)
            let user = process.user.padRight(width: 12)
            let command = process.command.truncated(to: 18).padRight(width: 18)
            let rawPath = process.workingDirectory ?? process.processPath ?? ""
            let project = rawPath.isEmpty ? "-" : shortProjectPath(rawPath)
            return "\(port) \(proto) \(pid) \(cpu) \(mem) \(user) \(command) \(project)"
        }

        private func formatMem(_ mb: Double) -> String {
            if mb >= 1024 { return String(format: "%.1fG", mb / 1024.0) }
            if mb >= 10 { return String(format: "%.0fM", mb) }
            return String(format: "%.1fM", mb)
        }

        private func outputJSON(_ processes: [PortProcess]) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(processes)
            if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
        }
    }
}

// MARK: - Kill Command
extension PortKiller {
    struct Kill: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Kill process listening on a specific port"
        )

        @Argument(help: "Port number to kill (prefix with ':' for shell-style input, e.g., :8080)")
        var port: String

        @Flag(name: .long, help: "Force kill without graceful termination")
        var force: Bool = false

        @Option(name: .long, help: "Timeout for graceful termination in milliseconds")
        var timeout: Int = 5000

        func run() throws {
            let portManager = PortManager()
            let portNumber = parsePort(port)

            guard portNumber > 0 else {
                print("Invalid port number: \(port)")
                throw ExitCode(1)
            }

            try portManager.killProcessOnPort(portNumber, force: force, timeout: timeout)
            print("✅ Process on port \(portNumber) has been terminated.")
        }

        private func parsePort(_ input: String) -> Int {
            let cleaned = input.hasPrefix(":") ? String(input.dropFirst()) : input
            return Int(cleaned) ?? 0
        }
    }
}

// MARK: - Interactive Command
extension PortKiller {
    struct Interactive: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Interactive mode to select and kill processes"
        )

        @Option(name: .shortAndLong, help: "Start of port range")
        var start: Int?

        @Option(name: .shortAndLong, help: "End of port range")
        var end: Int?

        func run() throws {
            let portManager = PortManager()
            let interactive = InteractiveMode(portManager: portManager)
            try interactive.start(startPort: start, endPort: end)
        }
    }
}

// MARK: - Kill All Command
extension PortKiller {
    struct KillAll: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Kill all processes (use with caution)"
        )

        @Option(name: .shortAndLong, help: "Start of port range")
        var start: Int?

        @Option(name: .shortAndLong, help: "End of port range")
        var end: Int?

        @Option(name: .shortAndLong, help: "Kill processes matching command pattern")
        var pattern: String?

        @Flag(name: .long, help: "Force kill without confirmation")
        var force: Bool = false
        @Flag(name: .long, help: "Skip confirmation before killing")
        var yes: Bool = false
        @Flag(name: .long, help: "Show what would be killed without actually killing")
        var dryRun: Bool = false

        func run() throws {
            let portManager = PortManager()
            var processes = try portManager.getListeningProcesses(startPort: start, endPort: end)

            // Filter by pattern if provided
            if let pattern = pattern, !pattern.isEmpty {
                let lowercasedPattern = pattern.lowercased()
                processes = processes.filter { $0.command.lowercased().contains(lowercasedPattern) }
            }

            if processes.isEmpty {
                print("No processes found matching the criteria.")
                return
            }

            if dryRun {
                print("🔍 Dry run - the following processes would be killed:")
                for process in processes.sorted(by: { $0.port < $1.port }) {
                    print("  • \(process.port): \(process.command) (pid: \(process.pid), user: \(process.user))")
                }
                print("\nTotal: \(processes.count) process(es)")
                return
            }

            if !yes {
                print("⚠️  This will kill \(processes.count) process(es):")
                for process in processes.sorted(by: { $0.port < $1.port }) {
                    print("  • \(process.port): \(process.command) (pid: \(process.pid), user: \(process.user))")
                }
                print("Add --yes to confirm, or re-run with `--force` + `--yes`.")
                return
            }

            try portManager.killAllProcesses(startPort: start, endPort: end, force: force, pattern: pattern)
            print("✅ All matching processes have been terminated.")
        }
    }
}

// MARK: - PID Command
extension PortKiller {
    struct PID: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Get the process ID for a port"
        )

        @Argument(help: "Port number (prefix with ':' for kill-style input)")
        var port: String

        @Flag(name: .shortAndLong, help: "Output only the PID number")
        var quiet: Bool = false

        func run() throws {
            let portManager = PortManager()
            let portNumber = parsePort(port)

            guard portNumber > 0 else {
                print("Invalid port number: \(port)")
                throw ExitCode(1)
            }

            guard let pid = portManager.getPID(forPort: portNumber) else {
                if !quiet {
                    print("No process found listening on port \(portNumber)")
                }
                throw ExitCode(1)
            }

            if quiet {
                print(pid)
            } else {
                print("Port \(portNumber) -> PID \(pid)")
            }
        }

        private func parsePort(_ input: String) -> Int {
            let cleaned = input.hasPrefix(":") ? String(input.dropFirst()) : input
            return Int(cleaned) ?? 0
        }
    }
}

// MARK: - PIDs Command
extension PortKiller {
    struct PIDs: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Get process IDs for multiple ports"
        )

        @Argument(help: "Port numbers (prefix with ':' for kill-style input, e.g., :3000 :8080 :5432)")
        var ports: [String]

        @Flag(name: .shortAndLong, help: "Output only the PIDs, one per line")
        var quiet: Bool = false

        @Flag(name: .long, help: "Show only ports that are in use")
        var occupiedOnly: Bool = false

        func run() throws {
            let portManager = PortManager()
            let portNumbers = ports.map { parsePort($0) }

            guard !portNumbers.contains(0) else {
                print("Invalid port number in input")
                throw ExitCode(1)
            }

            let results = portManager.getPIDs(forPorts: portNumbers)

            if results.isEmpty {
                if !quiet {
                    print("No processes found for the specified ports.")
                }
                return
            }

            if quiet {
                for (_, pid) in results.sorted(by: { $0.key < $1.key }) {
                    print(pid)
                }
            } else {
                print("\n🔍 Port -> PID Mapping:")
                print(String(repeating: "─", count: 40))

                let sorted = results.sorted { $0.key < $1.key }
                for (port, pid) in sorted {
                    print("Port \(port)".padRight(width: 12) + "-> PID \(pid)")
                }

                print(String(repeating: "─", count: 40))
                print("\nFound \(results.count) port(s) in use")
            }
        }

        private func parsePort(_ input: String) -> Int {
            let cleaned = input.hasPrefix(":") ? String(input.dropFirst()) : input
            return Int(cleaned) ?? 0
        }
    }
}

// MARK: - Find Command
extension PortKiller {
    struct Find: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Find available ports in a range"
        )

        @Option(name: .shortAndLong, help: "Start of port range (e.g., 3000)")
        var start: Int?

        @Option(name: .shortAndLong, help: "End of port range (e.g., 9000)")
        var end: Int?

        @Option(name: .shortAndLong, help: "Number of available ports to find")
        var count: Int = 1

        @Flag(name: .long, help: "Output in JSON format")
        var json: Bool = false

        func run() throws {
            let portManager = PortManager()
            let availablePorts = try portManager.findAvailablePorts(startPort: start, endPort: end, count: count)

            if availablePorts.isEmpty {
                print("No available ports found in the specified range.")
                return
            }

            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(availablePorts)
                if let jsonString = String(data: data, encoding: .utf8) {
                    print(jsonString)
                }
            } else {
                print("\n🔍 Available Ports:")
                print(String(repeating: "─", count: 40))
                for port in availablePorts {
                    print("  • \(port)")
                }
                print(String(repeating: "─", count: 40))
                print("\nFound \(availablePorts.count) available port(s)")
            }
        }
    }
}

// MARK: - Docker Command
extension PortKiller {
    struct Docker: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show Docker container information for ports"
        )

        @Option(name: .shortAndLong, help: "Start of port range")
        var start: Int?

        @Option(name: .shortAndLong, help: "End of port range")
        var end: Int?

        @Flag(name: .long, help: "Show only Docker-related processes")
        var dockerOnly: Bool = false

        func run() throws {
            let portManager = PortManager()
            let processes = try portManager.getListeningProcesses(startPort: start, endPort: end)

            // Filter for Docker processes
            let dockerProcesses = processes.filter { port in
                let command = port.command.lowercased()
                return Self.dockerProcessNames.contains(command) ||
                       command.contains("docker") ||
                       command.contains("containerd")
            }

            let displayProcesses = dockerOnly ? dockerProcesses : processes

            if displayProcesses.isEmpty {
                print("No Docker-related processes found.")
                return
            }

            print("\n🐳 Docker Processes:")
            print(String(repeating: "─", count: 80))
            print("PORT     PROTO   PID       USER              COMMAND")
            print(String(repeating: "─", count: 80))

            for process in displayProcesses.sorted(by: { $0.port < $1.port }) {
                let isDocker = Self.dockerProcessNames.contains(process.command.lowercased()) ||
                               process.command.lowercased().contains("docker") ||
                               process.command.lowercased().contains("containerd")
                let marker = isDocker ? "🐳" : "  "
                print("\(marker) \(process.port)".padRight(width: 8) +
                      "\(process.protocolName.uppercased())".padRight(width: 7) +
                      "\(process.pid)".padRight(width: 10) +
                      "\(process.user)".padRight(width: 17) +
                      process.command)
            }

            print(String(repeating: "─", count: 80))
            let dockerCount = dockerProcesses.count
            print("\nTotal: \(displayProcesses.count) process(es), \(dockerCount) Docker-related")
        }

        private static let dockerProcessNames: Set<String> = [
            "docker", "dockerd", "containerd", "docker-compose",
            "com.docker.hyperkit", "com.docker.vpnkit", "docker-proxy"
        ]
    }
}

// MARK: - Program PIDs Command
extension PortKiller {
    struct ProgramPids: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Get process IDs for a custom program"
        )

        @Option(name: .shortAndLong, help: "Program name to search for")
        var program: String

        @Flag(name: .shortAndLong, help: "Output only the PIDs, one per line")
        var quiet: Bool = false

        @Flag(name: .long, help: "Output in JSON format")
        var json: Bool = false

        func run() throws {
            let portManager = PortManager()
            let processes = portManager.getProcessesByName(names: [program])

            if processes.isEmpty {
                if !quiet {
                    print("No processes found for program '\(program)'")
                }
                return
            }

            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(processes)
                if let jsonString = String(data: data, encoding: .utf8) {
                    print(jsonString)
                }
                return
            }

            if quiet {
                for process in processes {
                    print(process.pid)
                }
            } else {
                print("\nPIDs for program '\(program)':")
                print(String(repeating: "─", count: 50))
                print("PID       USER              COMMAND")
                print(String(repeating: "─", count: 50))

                for process in processes.sorted(by: { $0.pid < $1.pid }) {
                    print("\(process.pid)".padRight(width: 10) +
                          "\(process.user)".padRight(width: 17) +
                          (process.fullCommand ?? process.command))
                }

                print(String(repeating: "─", count: 50))
                print("\nFound \(processes.count) process(es)")
            }
        }
    }
}

// MARK: - Program Kill Command
extension PortKiller {
    struct ProgramKill: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Kill all processes for a custom program"
        )

        @Option(name: .shortAndLong, help: "Program name to kill")
        var program: String

        @Flag(name: .long, help: "Force kill without graceful termination")
        var force: Bool = false

        @Flag(name: .long, help: "Skip confirmation before killing")
        var yes: Bool = false

        func run() throws {
            let portManager = PortManager()
            let processes = portManager.getProcessesByName(names: [program])

            if processes.isEmpty {
                print("No processes found for program '\(program)'")
                return
            }

            if !yes {
                print("\nThis will kill \(processes.count) process(es) for program '\(program)':")
                print(String(repeating: "─", count: 50))
                for process in processes.sorted(by: { $0.pid < $1.pid }) {
                    print("  • PID \(process.pid): \(process.user) - \(process.fullCommand ?? process.command)")
                }
                print(String(repeating: "─", count: 50))
                print("\nAdd --yes to confirm, or re-run with `--force` + `--yes`.")
                return
            }

            try portManager.killAllProcesses(named: [program], force: force)
            print("✅ All \(processes.count) process(es) for program '\(program)' have been terminated.")
        }
    }
}

// MARK: - Proxy Command
extension PortKiller {
    struct Proxy: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a SOCKS proxy tunnel through SSH"
        )

        @Option(name: .shortAndLong, help: "Local SOCKS proxy port")
        var port: Int = 1080

        @Option(name: .shortAndLong, help: "SSH user@host")
        var ssh: String

        @Option(name: .long, help: "Background process ID file")
        var pidFile: String?

        @Flag(name: .long, help: "Verbose output")
        var verbose: Bool = false

        func run() throws {
            print("\n🌐 Creating SOCKS proxy...")
            print("   Local port: \(port)")
            print("   SSH target: \(ssh)")
            print("")
            print("Command to run:")
            print("  ssh -D \(port) -N \(ssh)")
            print("")
            print("Then configure your browser/app to use:")
            print("  SOCKS5 proxy: localhost:\(port)")
            print("")
            print("Press Ctrl+C to stop the tunnel.")

            // Run the SSH command
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            task.arguments = ["-D", String(port), "-N", ssh]

            if verbose {
                task.standardOutput = FileHandle.standardOutput
                task.standardError = FileHandle.standardError
            } else {
                let outputPipe = Pipe()
                task.standardOutput = outputPipe
                task.standardError = outputPipe
            }

            if let pidFile = pidFile {
                try "\(task.processIdentifier)".write(toFile: pidFile, atomically: true, encoding: .utf8)
            }

            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                print("❌ Failed to start SSH tunnel: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - TUI Command
extension PortKiller {
    struct TUI: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Launch the rich terminal UI (portpilot-tui)"
        )

        func run() throws {
            // Look for portpilot-tui next to this binary, then in PATH
            let selfPath = CommandLine.arguments[0]
            let selfDir = (selfPath as NSString).deletingLastPathComponent
            let candidates = [
                "\(selfDir)/portpilot-tui",
                "/usr/local/bin/portpilot-tui",
            ]

            for path in candidates {
                if FileManager.default.isExecutableFile(atPath: path) {
                    // execv replaces this process entirely — terminal stays interactive
                    let cPath = strdup(path)!
                    var argv: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
                    execv(cPath, &argv)
                    // execv only returns on failure
                    free(cPath)
                }
            }

            // Fallback: try PATH via execvp
            let name = strdup("portpilot-tui")!
            var argv: [UnsafeMutablePointer<CChar>?] = [name, nil]
            execvp(name, &argv)
            free(name)

            // Only reached if exec failed
            print("portpilot-tui not found. Install it with:")
            print("  swift build -c release --product portpilot-tui")
            print("  sudo cp .build/release/portpilot-tui /usr/local/bin/")
            throw ExitCode(1)
        }
    }
}

// MARK: - Cronjobs Command
extension PortKiller {
    struct Cronjobs: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List scheduled cronjobs (user crontab and system cron)"
        )

        @Flag(name: .long, help: "Show only user crontab entries")
        var userOnly: Bool = false

        @Flag(name: .long, help: "Show only system cron entries")
        var systemOnly: Bool = false

        @Flag(name: .long, help: "Output in JSON format")
        var json: Bool = false

        func run() throws {
            let portManager = PortManager()
            let cronjobs = portManager.getCronjobs(userOnly: userOnly, systemOnly: systemOnly)

            if cronjobs.isEmpty {
                print("No cronjobs found.")
                return
            }

            if json {
                try outputJSON(cronjobs)
            } else {
                outputTable(cronjobs)
            }
        }

        private func outputTable(_ cronjobs: [CronjobEntry]) {
            print("\nScheduled Cronjobs:")
            print(String(repeating: "─", count: 100))
            print(headerRow())
            print(String(repeating: "─", count: 100))

            for job in cronjobs {
                print(row(job))
            }
            print(String(repeating: "─", count: 100))
            print("\nFound \(cronjobs.count) cronjob(s)")
        }

        private func headerRow() -> String {
            let schedule = "SCHEDULE".padRight(width: 18)
            let nextRun = "NEXT RUN".padRight(width: 20)
            let user = "USER".padRight(width: 12)
            let command = "COMMAND".padRight(width: 25)
            let source = "SOURCE"
            return "\(schedule) \(nextRun) \(user) \(command) \(source)"
        }

        private func row(_ job: CronjobEntry) -> String {
            let schedule = (job.scheduleHuman ?? job.schedule).truncated(to: 17).padRight(width: 18)
            let nextRun = formatNextRun(job.nextRun).padRight(width: 20)
            let user = (job.user ?? "-").padRight(width: 12)
            let command = job.command.truncated(to: 24).padRight(width: 25)
            let source = job.source == "user" ? "user" : shortSourcePath(job.source)
            return "\(schedule) \(nextRun) \(user) \(command) \(source)"
        }

        private func formatNextRun(_ date: Date?) -> String {
            guard let date = date else { return "-".padRight(width: 20) }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            let relative = relativeTime(from: date)
            return "\(formatter.string(from: date)) (\(relative))"
        }

        private func relativeTime(from date: Date) -> String {
            let interval = date.timeIntervalSinceNow
            if interval < 0 { return "past" }
            if interval < 60 { return "in \(Int(interval))s" }
            if interval < 3600 { return "in \(Int(interval / 60))m" }
            if interval < 86400 { return "in \(Int(interval / 3600))h" }
            return "in \(Int(interval / 86400))d"
        }

        private func shortSourcePath(_ path: String) -> String {
            if path == "user" { return "user" }
            let components = path.split(separator: "/").map(String.init)
            if components.count <= 3 { return path }
            return components.suffix(2).joined(separator: "/")
        }

        private func outputJSON(_ cronjobs: [CronjobEntry]) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cronjobs)
            if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
        }
    }
}

// MARK: - Connections Command
extension PortKiller {
    struct Connections: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all established network connections"
        )

        @Flag(name: .long, help: "Show only processes with suspicious connection counts (>50)")
        var suspect: Bool = false

        @Flag(name: .long, help: "Show only connections to blocklisted hosts (~/.portpilot/blocklist.txt)")
        var blocklist: Bool = false

        @Option(name: .long, help: "Kill the process with the given PID")
        var kill: Int?

        @Flag(name: .long, help: "Output in JSON format")
        var json: Bool = false

        func run() throws {
            let portManager = PortManager()

            if let pid = kill {
                try killProcess(pid)
                return
            }

            let connections = try portManager.getAllConnections()

            // Group by PID for display
            var grouped: [Int: [EstablishedConnection]] = [:]
            for conn in connections {
                grouped[conn.pid, default: []].append(conn)
            }

            var displayItems: [(pid: Int, processName: String, user: String, count: Int, remoteSample: String, isBlocklisted: Bool)] = []
            for (pid, conns) in grouped {
                let sample = conns.first?.remoteAddress ?? "-"
                let processName = conns.first?.processName ?? "unknown"
                let user = conns.first?.user ?? "unknown"
                let isBlocklisted = conns.contains { portManager.isBlocklisted(connection: $0) }
                displayItems.append((pid: pid, processName: processName, user: user, count: conns.count, remoteSample: sample, isBlocklisted: isBlocklisted))
            }

            // Sort by connection count descending
            displayItems.sort { $0.count > $1.count }

            // Filter to suspect if requested
            if suspect {
                displayItems = displayItems.filter { $0.count > 50 }
            }

            // Filter to blocklist if requested
            if blocklist {
                displayItems = displayItems.filter { $0.isBlocklisted }
            }

            if displayItems.isEmpty {
                if blocklist {
                    print("No blocklisted connections found.")
                } else {
                    print("No established connections found.")
                }
                return
            }

            if json {
                try outputJSON(connections)
            } else {
                outputTable(displayItems, portManager: portManager)
            }
        }

        private func outputTable(_ items: [(pid: Int, processName: String, user: String, count: Int, remoteSample: String, isBlocklisted: Bool)], portManager: PortManager) {
            let blocklistCount = items.filter { $0.isBlocklisted }.count
            let suspectCount = items.filter { $0.count > 50 }.count

            print("\nEstablished Connections:")
            print(String(repeating: "─", count: 100))

            if blocklistCount > 0 {
                print("🚨 \(blocklistCount) connection(s) to blocklisted host(s)")
                print(String(repeating: "─", count: 100))
            } else if suspectCount > 0 {
                print("⚠️  \(suspectCount) process(es) with suspicious connection counts (>50)")
                print(String(repeating: "─", count: 100))
            }

            print("REMOTE".padRight(width: 30) + "PROCESS".padRight(width: 18) + "PID".padRight(width: 8) + "USER".padRight(width: 12) + "COUNT")
            print(String(repeating: "─", count: 100))

            for item in items {
                let remote = item.remoteSample.padRight(width: 30)
                let process = item.processName.truncated(to: 17).padRight(width: 18)
                let pid = "\(item.pid)".padRight(width: 8)
                let user = item.user.padRight(width: 12)
                var countStr = "\(item.count)"
                if item.isBlocklisted {
                    countStr += " 🚨"
                } else if item.count > 50 {
                    countStr += " ⚠️"
                }
                print("\(remote) \(process) \(pid) \(user) \(countStr)")
            }
            print(String(repeating: "─", count: 100))
            print("\n\(items.count) process(es) with \(items.reduce(0) { $0 + $1.count }) total connections")
        }

        private func outputJSON(_ connections: [EstablishedConnection]) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(connections)
            if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
        }

        private func killProcess(_ pid: Int) throws {
            let signal = "KILL"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/kill")
            process.arguments = ["-s", signal, "\(pid)"]
            try process.run()
            process.waitUntilExit()
            print("✅ Process \(pid) has been terminated.")
        }
    }
}

// MARK: - Main Command
@main
struct PortKiller: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A tiny CLI for viewing and clearing ports in use by running processes.",
        subcommands: [List.self, Kill.self, Interactive.self, KillAll.self, PID.self, PIDs.self, Find.self, Docker.self, ProgramPids.self, ProgramKill.self, Proxy.self, TUI.self, Cronjobs.self, Connections.self],
        defaultSubcommand: List.self
    )
}

// MARK: - Extensions
extension String {
    func padRight(width: Int) -> String {
        if self.count >= width { return String(self.prefix(width)) }
        return self + String(repeating: " ", count: width - self.count)
    }

    func truncated(to length: Int) -> String {
        guard self.count > length, length >= 4 else {
            return self
        }
        return String(self.prefix(length - 3)) + "..."
    }
}

/// Shorten an absolute path to just the project name (last 2-3 meaningful components)
func shortProjectPath(_ path: String) -> String {
    let components = path.split(separator: "/").map(String.init)
    guard components.count >= 2 else { return path }

    // Skip common uninteresting prefixes
    var startIdx = 0
    for (i, comp) in components.enumerated() {
        if ["home", "mnt", "Users", "c", "usr", "var"].contains(comp) { continue }
        if i > 0, ["home", "Users"].contains(components[i - 1]) { continue }
        startIdx = i
        break
    }

    let meaningful = Array(components[startIdx...])
    if meaningful.count <= 3 {
        return meaningful.joined(separator: "/")
    }
    return meaningful.suffix(3).joined(separator: "/")
}
