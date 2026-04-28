import Foundation
import Combine

// MARK: - Live Metrics History

/// Ring-buffer sampler that powers every sparkline in the app.
///
/// I tick on a fixed 2-second cadence, snapshot the view model, and push onto
/// bounded per-metric rings so the menubar strip, the main-window strip, and
/// the inspector all animate from a shared, truthful source. ~40 samples at
/// 2s each gives me roughly 80 seconds of visible history per metric.
@MainActor
final class LiveMetricsHistory: ObservableObject {
    // ~40 samples × 2s cadence = 80s of visible history per metric.
    private let capacity = 40
    private let sampleInterval: TimeInterval = 2

    /// Count of active (non-socket) listening ports, sampled every 2s.
    @Published private(set) var active: [Double] = []
    /// Count of Unix domain sockets tracked, sampled every 2s.
    @Published private(set) var sockets: [Double] = []
    /// Count of established connections across all ports, sampled every 2s.
    @Published private(set) var connections: [Double] = []
    /// Summed CPU% across every active port, sampled every 2s.
    @Published private(set) var cpu: [Double] = []
    /// Per-port CPU% history keyed by `PortProcess.id`, sampled every 2s.
    /// I evict entries for ports that vanish so the dictionary stays bounded.
    @Published private(set) var perPortCPU: [String: [Double]] = [:]

    private weak var viewModel: PortViewModel?
    private var timer: Timer?

    /// Binds to a view model and starts the 2-second sampling timer. Safe to
    /// call more than once — I invalidate any prior timer first.
    /// - Parameter viewModel: The `PortViewModel` I snapshot on every tick.
    func start(viewModel: PortViewModel) {
        self.viewModel = viewModel
        tick()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// Tears down the sampling timer. I call this on teardown so I don't
    /// keep ticking after the owning view has disappeared.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// I snapshot the current viewModel state once and push it onto every ring.
    private func tick() {
        guard let vm = viewModel else { return }
        let activePorts = vm.ports.filter { !$0.isUnixSocket }
        let socketCount = vm.ports.filter { $0.isUnixSocket }.count
        let connCount = vm.allConnections.count
        let totalCPU = activePorts.reduce(0.0) { $0 + ($1.cpuUsage ?? 0) }

        push(&active, Double(activePorts.count))
        push(&sockets, Double(socketCount))
        push(&connections, Double(connCount))
        push(&cpu, totalCPU)

        var updated = perPortCPU
        var liveIDs = Set<String>()
        for port in activePorts {
            liveIDs.insert(port.id)
            var history = updated[port.id] ?? []
            push(&history, port.cpuUsage ?? 0)
            updated[port.id] = history
        }
        // Evict history for ports that have vanished so the dict stays bounded.
        for key in updated.keys where !liveIDs.contains(key) {
            updated.removeValue(forKey: key)
        }
        perPortCPU = updated
    }

    private func push(_ ring: inout [Double], _ value: Double) {
        ring.append(value)
        if ring.count > capacity { ring.removeFirst(ring.count - capacity) }
    }

    /// Returns the ring of per-port CPU% samples for `port`, or an empty array
    /// if I haven't seen the port yet.
    /// - Parameter port: The port whose CPU history the caller wants to plot.
    func history(for port: PortProcess) -> [Double] {
        perPortCPU[port.id] ?? []
    }
}
