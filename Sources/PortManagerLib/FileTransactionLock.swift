import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Serializes a file-backed read/modify/write transaction both within this
/// process and, on POSIX platforms, across PortPilot processes.
///
/// Atomic replacement prevents torn files; this lock prevents two writers
/// from both reading the same old value and losing one update.
enum FileTransactionLock {
    private static let registryLock = NSLock()
    private static var processLocks: [String: NSLock] = [:]

    static func withExclusiveLock<T>(at lockURL: URL, _ body: () throws -> T) throws -> T {
        let processLock = lockForPath(lockURL.standardizedFileURL.path)
        processLock.lock()
        defer { processLock.unlock() }

        #if canImport(Darwin) || canImport(Glibc)
        let flags = O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW
        let descriptor = open(lockURL.path, flags, mode_t(0o600))
        guard descriptor >= 0 else { throw posixError() }
        defer { _ = close(descriptor) }

        guard fchmod(descriptor, mode_t(0o600)) == 0 else { throw posixError() }
        guard flock(descriptor, LOCK_EX) == 0 else { throw posixError() }
        defer { _ = flock(descriptor, LOCK_UN) }
        #endif

        return try body()
    }

    private static func lockForPath(_ path: String) -> NSLock {
        registryLock.lock()
        defer { registryLock.unlock() }
        if let existing = processLocks[path] { return existing }
        let created = NSLock()
        processLocks[path] = created
        return created
    }

    #if canImport(Darwin) || canImport(Glibc)
    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    #endif
}
