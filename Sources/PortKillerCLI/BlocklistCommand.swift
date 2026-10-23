// BlocklistCommand.swift — `portpilot blocklist` subcommand.
//
// Why a subcommand instead of hand-editing the file:
//   Detection was read-only from the CLI — you could SEE blocklisted
//   connections but blocking a hostile host meant opening
//   ~/.portpilot/blocklist.txt in an editor mid-incident. These three verbs
//   close that loop: list / add / remove, all through BlocklistStore so the
//   file format keeps its single owner.
//
// Usage:
//   portpilot blocklist list
//   portpilot blocklist add 203.0.113.9
//   portpilot blocklist add .evil.com
//   portpilot blocklist remove 203.0.113.9

import ArgumentParser
import Foundation
#if canImport(PortManagerLib)
import PortManagerLib
#endif

struct BlocklistCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "blocklist",
        abstract: "List, add, or remove blocklisted hosts (~/.portpilot/blocklist.txt)",
        subcommands: [List.self, Add.self, Remove.self],
        defaultSubcommand: List.self
    )
}

extension BlocklistCommand {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List blocklisted hosts")

        func run() throws {
            let entries = BlocklistStore().entries()
            if entries.isEmpty {
                print("Blocklist is empty. Add hosts with: portpilot blocklist add <host|IP|CIDR>")
                return
            }
            print("Blocklisted hosts (\(entries.count)):")
            for entry in entries {
                print("  • \(entry)")
            }
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Blocklist a host, IP, domain suffix (.evil.com), or CIDR")

        @Argument(help: "Entry to blocklist, e.g. 203.0.113.9, .evil.com, 192.168.1.0/24")
        var entry: String

        func run() throws {
            do {
                if try BlocklistStore().add(entry) {
                    print("✅ Blocklisted \(entry)")
                } else {
                    print("Already blocklisted: \(entry)")
                }
            } catch {
                print("❌ \(error)")
                throw ExitCode(1)
            }
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove a host from the blocklist")

        @Argument(help: "Entry to remove")
        var entry: String

        func run() throws {
            do {
                if try BlocklistStore().remove(entry) {
                    print("✅ Removed \(entry) from blocklist")
                } else {
                    print("Not on the blocklist: \(entry)")
                    throw ExitCode(1)
                }
            } catch {
                print("❌ \(error)")
                throw ExitCode(1)
            }
        }
    }
}
