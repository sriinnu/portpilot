import Foundation
import ArgumentParser
import PortManagerLib

@main
struct PortKiller: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A tiny CLI for viewing and clearing ports in use by running processes.",
        subcommands: [List.self, Kill.self, Interactive.self, KillAll.self],
        defaultSubcommand: List.self
    )
}

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
            print(String(repeating: "─", count: 80))
            print(headerRow())
            print(String(repeating: "─", count: 80))
            
            for process in processes.sorted(by: { $0.port < $1.port }) {
                print(row(process))
            }
            print(String(repeating: "─", count: 80))
            print("\nFound \(processes.count) process(es)")
        }

        private func headerRow() -> String {
            let port = "PORT".padRight(width: 8)
            let proto = "PROTO".padRight(width: 6)
            let pid = "PID".padRight(width: 8)
            let user = "USER".padRight(width: 18)
            return "\(port) \(proto) \(pid) \(user) COMMAND"
        }
        
        private func row(_ process: PortProcess) -> String {
            let port = "\(process.port)".padRight(width: 8)
            let proto = process.protocolName.uppercased().padRight(width: 6)
            let pid = "\(process.pid)".padRight(width: 8)
            let user = process.user.padRight(width: 18)
            let command = process.command.truncated(to: 28)
            return "\(port) \(proto) \(pid) \(user) \(command)"
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
        
        @Argument(help: "Port number to kill")
        var port: Int
        
        @Flag(name: .long, help: "Force kill without graceful termination")
        var force: Bool = false
        
        @Option(name: .long, help: "Timeout for graceful termination in milliseconds")
        var timeout: Int = 5000
        
        func run() throws {
            let portManager = PortManager()
            try portManager.killProcessOnPort(port, force: force, timeout: timeout)
            print("✅ Process on port \(port) has been terminated.")
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
        
        @Flag(name: .long, help: "Force kill without confirmation")
        var force: Bool = false
        @Flag(name: .long, help: "Skip confirmation before killing")
        var yes: Bool = false
        
        func run() throws {
            let portManager = PortManager()
            if !yes {
                let processes = try portManager.getListeningProcesses(startPort: start, endPort: end)
                guard !processes.isEmpty else {
                    print("No processes found for the specified range.")
                    return
                }
                
                print("⚠️  This will kill \(processes.count) process(es):")
                for process in processes.sorted(by: { $0.port < $1.port }) {
                    print("  • \(process.port): \(process.command) (pid: \(process.pid), user: \(process.user))")
                }
                print("Add --yes to confirm, or re-run with `--force` + `--yes`.")
                return
            }
            
            try portManager.killAllProcesses(startPort: start, endPort: end, force: force)
            print("✅ All matching processes have been terminated.")
        }
    }
}

// MARK: - Extensions
extension String {
    func padRight(width: Int) -> String {
        if self.count >= width { return String(self.prefix(width)) }
        return self + String(repeating: " ", count: width - self.count)
    }

    func truncated(to length: Int) -> String {
        guard self.count > length else {
            return self
        }
        return String(self.prefix(length - 3)) + "..."
    }
}
