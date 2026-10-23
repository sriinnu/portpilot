import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Small security primitives shared by persistence and subprocess code.
/// Kept internal so callers cannot accidentally treat them as a public API.
enum SecureFilePermissions {
    static let privateDirectory = 0o700
    static let privateFile = 0o600

    static func ensurePrivateDirectory(_ url: URL, secureExisting: Bool = true) throws {
        var isDirectory: ObjCBool = false
        let existed = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if existed && !isDirectory.boolValue {
            throw CocoaError(.fileWriteFileExists)
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        #if !os(Windows)
        if secureExisting || !existed {
            try FileManager.default.setAttributes(
                [.posixPermissions: privateDirectory],
                ofItemAtPath: url.path
            )
        }
        #endif
    }

    static func enforcePrivateFile(_ url: URL) throws {
        #if !os(Windows)
        try FileManager.default.setAttributes(
            [.posixPermissions: privateFile],
            ofItemAtPath: url.path
        )
        #endif
    }

    /// Write through a private sibling file, then atomically replace the
    /// destination. The final path is never visible with the process umask's
    /// potentially world-readable default permissions.
    static func writePrivateData(
        _ data: Data,
        to url: URL,
        secureExistingDirectory: Bool = true
    ) throws {
        let directory = url.deletingLastPathComponent()
        try ensurePrivateDirectory(directory, secureExisting: secureExistingDirectory)

        let temporary = directory.appendingPathComponent(".portpilot-\(UUID().uuidString).tmp")
        let attributes: [FileAttributeKey: Any]
        #if os(Windows)
        attributes = [:]
        #else
        attributes = [.posixPermissions: privateFile]
        #endif

        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: attributes) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            try enforcePrivateFile(temporary)

            #if canImport(Darwin) || canImport(Glibc)
            // A sibling POSIX rename atomically creates or replaces the path.
            // Avoid swift-corelibs-foundation's failing replaceItemAt path on
            // Linux, while retaining private-before-write permissions.
            guard rename(temporary.path, url.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            #else
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: url)
            }
            #endif
            try enforcePrivateFile(url)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    static func repairPrivateFileIfPresent(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? enforcePrivateFile(url)
    }
}

/// Retains at most `limit` bytes while continuing to drain a child process.
/// This prevents a noisy command from deadlocking on a full pipe without
/// letting its output grow PortPilot's memory without bound.
struct BoundedOutputBuffer {
    let limit: Int
    private(set) var data = Data()
    private(set) var wasTruncated = false

    init(limit: Int) {
        self.limit = max(0, limit)
    }

    mutating func append(_ chunk: Data) {
        let remaining = max(0, limit - data.count)
        if remaining > 0 {
            data.append(contentsOf: chunk.prefix(remaining))
        }
        if chunk.count > remaining {
            wasTruncated = true
        }
    }
}
