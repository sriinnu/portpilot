import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Fixed, numeric port filters only. No shell, arbitrary BPF, name resolution,
/// promiscuous mode, payload printing, or on-disk capture.
public struct PacketCaptureRequest: Sendable {
    public let interface: String
    public let port: Int
    public let transport: String
    public let duration: TimeInterval
    public let packetLimit: Int
    public init(interface: String, port: Int, transport: String, duration: TimeInterval = 10,
                packetLimit: Int = 200) throws {
        guard !interface.isEmpty, interface.utf8.count <= 32,
              interface.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
                  || (97...122).contains($0) || $0 == 95 }),
              (1...65535).contains(port), ["tcp", "udp"].contains(transport.lowercased()),
              duration.isFinite, (1...30).contains(duration), (1...200).contains(packetLimit)
        else { throw CaptureError.invalidRequest }
        self.interface = interface; self.port = port; self.transport = transport.lowercased()
        self.duration = duration; self.packetLimit = packetLimit
    }
    public var arguments: [String] {
        ["-i", interface, "-p", "-n", "-q", "-tt", "-l", "-s", "96",
         "-c", String(packetLimit), "\(transport) port \(port)"]
    }
    public enum CaptureError: Error { case invalidRequest }
}

public struct PacketSummary: Identifiable, Equatable, Sendable {
    public var id: String { "\(timestamp) \(source) \(destination) \(detail)" }
    public let timestamp: String
    public let source: String
    public let destination: String
    public let detail: String
    /// Only tcpdump's numeric endpoint summary lines; ignore diagnostics/decoder continuations.
    public static func parse(_ line: String) -> Self? {
        let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count >= 7, Double(fields[0]) != nil,
              ["IP", "IP6"].contains(fields[1]), fields[3] == ">",
              fields[4].hasSuffix(":"), ["tcp", "UDP,"].contains(fields[5]) else { return nil }
        return Self(timestamp: fields[0], source: fields[2],
                    destination: String(fields[4].dropLast()), detail: fields[5...].joined(separator: " "))
    }
}

public struct PacketCaptureResult: Sendable {
    public let packets: [PacketSummary]
    public let message: String
    public let failed: Bool
    public let truncated: Bool
}

/// One-use bounded subprocess. cancel only requests cancellation; the worker validates
/// the child incarnation before delivering signals. Results arrive after child settlement.
public final class PacketCaptureSession: @unchecked Sendable {
    private let request: PacketCaptureRequest
    private let executable: String
    private let arguments: [String]
    private let lock = NSLock()
    private var cancelled = false
    private var used = false
    private var cleanupConfirmed = true
    private let finished = DispatchGroup()
    private let childFinished = DispatchGroup()
    private var runningChild: Process?
    private let identityProvider: @Sendable (Int) -> String?
    private var buffer = BoundedOutputBuffer(limit: 128 * 1024)

    public convenience init(request: PacketCaptureRequest) {
        self.init(request: request, executable: "/usr/sbin/tcpdump", arguments: request.arguments)
    }
    // Synthetic local subprocesses in regression tests; never exposed as a UI option.
    init(request: PacketCaptureRequest, executable: String, arguments: [String],
         identityProvider: @escaping @Sendable (Int) -> String? = { PortManager().processIncarnationToken(pid: $0) }) {
        self.request = request; self.executable = executable; self.arguments = arguments
        self.identityProvider = identityProvider
        finished.enter()
    }
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public func waitUntilFinished(timeout: TimeInterval) -> Bool {
        let deadline = DispatchTime.now() + max(0, timeout)
        guard finished.wait(timeout: deadline) == .success,
              childFinished.wait(timeout: deadline) == .success else { return false }
        lock.lock(); defer { lock.unlock() }
        return cleanupConfirmed
    }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    public func run() -> PacketCaptureResult {
        lock.lock()
        let alreadyUsed = used
        used = true
        lock.unlock()
        if alreadyUsed {
            return PacketCaptureResult(packets: [], message: "Capture session already used.", failed: true, truncated: false)
        }
        defer { finished.leave() }
        if isCancelled {
            return PacketCaptureResult(packets: [], message: "Capture cancelled.", failed: false, truncated: false)
        }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = arguments
        child.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]
        let pipe = Pipe()
        child.standardOutput = pipe; child.standardError = pipe
        child.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        let readFD = pipe.fileHandleForReading.fileDescriptor
        let flags = fcntl(readFD, F_GETFL)
        guard flags >= 0, fcntl(readFD, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
            return PacketCaptureResult(packets: [], message: "Could not prepare the packet capture output pipe.",
                                       failed: true, truncated: false)
        }
        var reachedEOF = false
        var readFailed = false
        var readBuffer = [UInt8](repeating: 0, count: 8192)
        // FileHandle's EOF readability callback is not delivered consistently
        // for short-lived children on Linux. Confirm EOF from read() itself.
        // Bound each batch so a noisy child cannot prevent deadline checks.
        func drainAvailable() {
            guard !reachedEOF else { return }
            for _ in 0..<32 {
                let count = read(readFD, &readBuffer, readBuffer.count)
                if count > 0 {
                    lock.lock(); buffer.append(Data(readBuffer.prefix(count))); lock.unlock()
                } else if count == 0 {
                    reachedEOF = true
                    return
                } else if errno == EINTR {
                    continue
                } else if errno == EAGAIN || errno == EWOULDBLOCK {
                    return
                } else {
                    readFailed = true
                    reachedEOF = true
                    return
                }
            }
        }
        childFinished.enter()
        lock.lock(); cleanupConfirmed = false; runningChild = child; lock.unlock()
        child.terminationHandler = { [weak self, childFinished] _ in
            if let self {
                self.lock.lock()
                self.cleanupConfirmed = true
                self.runningChild = nil
                self.lock.unlock()
            }
            childFinished.leave()
            exited.signal()
        }
        do { try child.run() }
        catch {
            child.terminationHandler = nil
            lock.lock(); cleanupConfirmed = true; runningChild = nil; lock.unlock()
            childFinished.leave()
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
            return PacketCaptureResult(packets: [], message: "Could not start the system packet capture tool.",
                                       failed: true, truncated: false)
        }
        try? pipe.fileHandleForWriting.close()
        let pid = Int(child.processIdentifier)
        let token = identityProvider(pid)
        let deadline = ProcessInfo.processInfo.systemUptime + request.duration
        var stoppedByLimit = false
        var settled = false
        while !settled {
            drainAvailable()
            settled = exited.wait(timeout: .now() + 0.05) == .success
            if settled { break }
            if isCancelled || ProcessInfo.processInfo.systemUptime >= deadline {
                stoppedByLimit = true
                if ProcessEscalationPolicy.permits(expectedToken: token, currentToken: identityProvider(pid)) {
                    kill(child.processIdentifier, SIGTERM)
                }
                settled = exited.wait(timeout: .now() + 1) == .success
                if !settled {
                    if ProcessEscalationPolicy.permits(expectedToken: token, currentToken: identityProvider(pid)) {
                        kill(child.processIdentifier, SIGKILL)
                    }
                    settled = exited.wait(timeout: .now() + 1) == .success
                }
                break
            }
        }
        let drainDeadline = ProcessInfo.processInfo.systemUptime + 1
        repeat {
            drainAvailable()
            if reachedEOF { break }
            Thread.sleep(forTimeInterval: 0.01)
        } while ProcessInfo.processInfo.systemUptime < drainDeadline
        try? pipe.fileHandleForReading.close()
        lock.lock()
        cleanupConfirmed = cleanupConfirmed || settled
        let text = String(decoding: buffer.data, as: UTF8.self)
        let truncated = buffer.wasTruncated || !reachedEOF || readFailed
        lock.unlock()
        let packets = Array(text.split(separator: "\n").compactMap { PacketSummary.parse(String($0)) }.prefix(request.packetLimit))
        let denied = text.localizedCaseInsensitiveContains("permission denied")
            || text.localizedCaseInsensitiveContains("operation not permitted")
            || text.localizedCaseInsensitiveContains("you don't have permission")
        let failed = !settled || readFailed || (!stoppedByLimit && child.terminationStatus != 0) || denied
        let message: String
        if !settled { message = "Capture cleanup could not be confirmed. Review the system capture tool before starting another capture." }
        else if denied { message = "Capture unavailable: this user cannot access the interface's capture device. PortPilot does not elevate privileges." }
        else if failed { message = "Capture failed on this interface. No complete observation is available." }
        else if isCancelled { message = "Capture stopped. Partial observations shown." }
        else if stoppedByLimit { message = "Timed capture finished. Only packets observed during this interval are shown." }
        else { message = "Packet limit reached or capture ended." }
        return PacketCaptureResult(packets: packets, message: message, failed: failed, truncated: truncated)
    }
}
