import Foundation

// MARK: - Docker CLI Access
// The app used to shell out to a hardcoded /usr/local/bin/docker with
// waitUntilExit-then-read pipes and try?-swallowed launch errors. This façade
// routes every docker call through the safe runner (drain-before-wait, real
// timeout, honest exit status) and resolves the binary like a person would.

/// One running container, as `docker ps` reports it. Lives in the lib so
/// the lookup and the model travel together.
public struct DockerInfo: Identifiable, Equatable, Sendable {
    public let containerId: String
    public let containerName: String
    public let imageName: String
    public let status: String
    public var id: String { containerId }

    public init(containerId: String, containerName: String, imageName: String, status: String) {
        self.containerId = containerId
        self.containerName = containerName
        self.imageName = imageName
        self.status = status
    }
}

extension PortManager {

    /// The container whose published ports include `port`, if any. Two docker
    /// calls worst case (`ps`, then `port` per candidate) — call off the main
    /// thread. nil when docker is missing, unreachable, or nothing maps `port`.
    public static func getContainerInfo(forPort port: Int) -> DockerInfo? {
        guard let psOutput = dockerRun(["ps", "--format", "{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}"]) else {
            return nil
        }
        for line in psOutput.components(separatedBy: "\n") {
            guard !line.isEmpty else { continue }
            let parts = line.split(separator: "|")
            guard parts.count >= 4 else { continue }

let containerId = String(parts[0])
if let ports = dockerRun(["port", containerId]),
   ports.split(separator: "\n").contains(where: { line in
       guard let r = line.range(of: ":\(port)") else { return false }
       let after = line[r.upperBound...]
       return after.isEmpty || !after.first!.isNumber
   }) || ports.contains("\(port)/") {
                return DockerInfo(
                    containerId: containerId,
                    containerName: String(parts[1]),
                    imageName: String(parts[2]),
                    status: String(parts[3])
                )
            }
        }
        return nil
    }


    /// Candidate docker binaries in preference order. Docker Desktop and
    /// OrbStack both symlink into /usr/local/bin; Homebrew's docker-cli
    /// installs to /opt/homebrew/bin (arm) or /usr/local/bin (intel); some
    /// setups expose /usr/bin/docker.
    public static let dockerBinaryCandidates = [
        "/usr/local/bin/docker",
        "/opt/homebrew/bin/docker",
        "/usr/bin/docker"
    ]

    /// First installed docker binary, or nil when docker isn't on this box.
    public static func dockerBinary() -> String? {
        dockerBinaryCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Run `docker <args>` and return trimmed stdout.
    /// nil on any failure: not installed, launch error, timeout, or non-zero
    /// exit. Callers treat nil as "no docker answer", never as empty output.
    public static func dockerRun(_ args: [String], timeout: TimeInterval = 10) -> String? {
        guard let binary = dockerBinary() else { return nil }
        let result = PortManager().runProcess(binary, arguments: args, timeout: timeout)
        guard result.exitStatus == 0, !result.timedOut else { return nil }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Run `docker <args>` disregarding output; returns whether the command
    /// ran to a zero exit within the timeout. For stop/restart-style calls.
    @discardableResult
    public static func dockerRunQuiet(_ args: [String], timeout: TimeInterval = 30) -> Bool {
        guard let binary = dockerBinary() else { return false }
        let result = PortManager().runProcess(binary, arguments: args, timeout: timeout)
        return result.exitStatus == 0 && !result.timedOut
    }
}
