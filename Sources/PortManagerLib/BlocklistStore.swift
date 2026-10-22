// BlocklistStore.swift — Read/write manager for ~/.portpilot/blocklist.txt.
//
// Why this exists:
//   Detection was read-only: PortManager could MATCH the blocklist but
//   nothing in the codebase could EDIT it — every blocklist change meant
//   hand-editing the file. The Security Center's "Block remote" action, the
//   `portpilot blocklist add/remove` CLI, and future auto-block all funnel
//   through this one type so the file format has a single owner.
//
// Format contract (shared with PortManager.loadBlocklistFromDisk):
//   - One entry per line: domain, `.suffix`, exact IPv4/IPv6, or IPv4 CIDR.
//   - `#` lines are comments and blank lines are ignored. Comment text is
//     retained on mutation, while surrounding whitespace and blank lines are
//     normalized.
//   - Matching is case-insensitive for hostnames; entries store trimmed.
//
// Concurrency: a private sibling lock file spans the full read-modify-write
// transaction. Atomic replacement prevents torn files; the advisory lock
// prevents concurrent app/CLI writers from losing one another's edits.

import Foundation

/// Errors with user-facing descriptions — CLI prints `description`, the app
/// surfaces it via `raiseError`.
public enum BlocklistError: Error, CustomStringConvertible {
    case invalidEntry(String)
    case ioError(String)

    public var description: String {
        switch self {
        case .invalidEntry(let entry):
            return "Invalid blocklist entry: '\(entry)'. Use a domain, .suffix, IP, or CIDR."
        case .ioError(let detail):
            return "Blocklist file error: \(detail)"
        }
    }
}

/// Single owner for blocklist reads and edits.
public struct BlocklistStore: Sendable {
    private let fileURL: URL
    private let transactionLockURL: URL
    private let ownsDirectoryPermissions: Bool

    /// - Parameter path: Full path to blocklist.txt. Defaults to
    ///   `~/.portpilot/blocklist.txt` (same path PortManager reads).
    public init(path: String? = nil) {
        if let path {
            self.fileURL = URL(fileURLWithPath: path)
            self.ownsDirectoryPermissions = false
        } else {
            self.fileURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".portpilot/blocklist.txt")
            self.ownsDirectoryPermissions = true
        }
        self.transactionLockURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".\(fileURL.lastPathComponent).lock")
        try? SecureFilePermissions.ensurePrivateDirectory(
            fileURL.deletingLastPathComponent(),
            secureExisting: ownsDirectoryPermissions
        )
        SecureFilePermissions.repairPrivateFileIfPresent(fileURL)
    }

    /// Active entries (comments and blanks excluded), in file order.
    public func entries() -> [String] {
        allLines().filter { Self.isEntry($0) }
    }

    /// Append an entry. Returns false (no write) when already listed.
    /// - Throws: BlocklistError.invalidEntry for empty or malformed input.
    @discardableResult
    public func add(_ entry: String) throws -> Bool {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", !trimmed.hasPrefix("#"), !trimmed.contains(" ") else {
            throw BlocklistError.invalidEntry(entry)
        }
        do {
            return try FileTransactionLock.withExclusiveLock(at: transactionLockURL) {
                var lines = try allLinesUnlocked()
                let lowered = lines.map { $0.lowercased() }
                guard !lowered.contains(trimmed.lowercased()) else { return false }
                lines.append(trimmed)
                try writeUnlocked(lines)
                return true
            }
        } catch let error as BlocklistError {
            throw error
        } catch {
            throw BlocklistError.ioError(error.localizedDescription)
        }
    }

    /// Remove an entry (case-insensitive). Returns false when not listed.
    @discardableResult
    public func remove(_ entry: String) throws -> Bool {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            return try FileTransactionLock.withExclusiveLock(at: transactionLockURL) {
                let lines = try allLinesUnlocked()
                let kept = lines.filter { $0.lowercased() != trimmed.lowercased() }
                guard kept.count != lines.count else { return false }
                try writeUnlocked(kept)
                return true
            }
        } catch let error as BlocklistError {
            throw error
        } catch {
            throw BlocklistError.ioError(error.localizedDescription)
        }
    }

    // MARK: - Private file handling

    private static func isEntry(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.hasPrefix("#")
    }

    private func allLines() -> [String] {
        // Atomic replacement guarantees a reader sees either the complete old
        // file or the complete new file, so reads do not need to queue behind
        // a potentially slow writer.
        (try? allLinesUnlocked()) ?? []
    }

    private func allLinesUnlocked() throws -> [String] {
        let content: String
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            // A missing blocklist is the valid empty state. Any failure to read
            // an existing file must abort mutation rather than replacing all
            // existing protections with a partial new list.
            guard Self.isMissingFileError(error) else {
                throw BlocklistError.ioError(error.localizedDescription)
            }
            return []
        }
        // Retain comment text while normalizing surrounding whitespace; drop
        // blank lines for a tidy file.
        return content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func isMissingFileError(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        while let candidate = current {
            if candidate.domain == NSCocoaErrorDomain,
               candidate.code == CocoaError.Code.fileReadNoSuchFile.rawValue {
                return true
            }
            if candidate.domain == NSPOSIXErrorDomain,
               candidate.code == Int(POSIXErrorCode.ENOENT.rawValue) {
                return true
            }
            let underlying = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
            current = underlying === candidate ? nil : underlying
        }
        return false
    }

    /// The transaction lock must be held by the caller.
    private func writeUnlocked(_ lines: [String]) throws {
        do {
            let content = lines.joined(separator: "\n") + "\n"
            try SecureFilePermissions.writePrivateData(
                Data(content.utf8),
                to: fileURL,
                secureExistingDirectory: ownsDirectoryPermissions
            )
        } catch {
            throw BlocklistError.ioError(error.localizedDescription)
        }
    }
}
