import Foundation

/// Port guard: armed enforcement over specific ports. Whatever holds a
/// port when the guard is armed is grandfathered and left alone; anything
/// that binds it afterwards gets TERM'd (escalating to KILL) and logged
/// loudly.
///
/// Enforcement is a pid-level sweep, not a state-change listener: a
/// squatter that replaces a dying holder between two ticks never shows a
/// free→occupied transition, but the pid diff still catches it. The sweep
/// runs on a private utility queue on the store's own timer — armed
/// whenever guards exist, regardless of the background-monitoring toggle.
///
/// Confinement: `guardedPorts` is @Published and main-confined (UI reads
/// and enables/disables happen on main); `armedPorts`, `grandfatheredPids`,
/// the timer, and the generation counter are queue-confined.
final class PortGuardStore: ObservableObject {
    @Published private(set) var guardedPorts: [Int] = []

    /// Wired by the owner after init — the VM's error hook captures self,
    /// which isn't legal until every member is initialized. nil drops errors.
    var onError: ((String) -> Void)?

    private let log: ActivityLogStore
    private let portManager = PortManager()
    private let queue = DispatchQueue(label: "com.portpilot.guard", qos: .utility)
    /// Queue-confined: starts/stops with the armed-port list.
    private var timer: DispatchSourceTimer?
    /// Queue-confined: skips a sweep when the previous one (slow lsof or a
    /// TERM wait) is still running.
    private var sweepInProgress = false
    /// Queue-confined mirror of `guardedPorts` — the sweep's port list.
    private var armedPorts: [Int] = []
    /// Queue-confined. Key present = snapshot landed ([] = port was free);
    /// key absent = snapshot still in flight, enforcement holds fire.
    private var grandfatheredPids: [Int: Set<Int>] = [:]
    /// Queue-confined: bumped on disarm so a late snapshot completion from
    /// the disarmed generation lands nowhere.
    private var generation = 0

    init(log: ActivityLogStore) {
        self.log = log

        // Persisted guards survive relaunch — but pids don't. Whatever holds
        // the guarded ports right now gets grandfathered so launching
        // PortPilot never turns into a surprise massacre.
        let ports = AppSettings.shared.guardedPorts.sorted()
        guardedPorts = ports
        queue.async { [weak self] in
            guard let self else { return }
            self.armedPorts = ports
            self.snapshotGrandfathers(for: ports, reason: "restored")
        }
    }

    // MARK: - Arming

    /// Arm a guard. Returns nil on success, or a user-facing reason the
    /// port can't be guarded (invalid range, reserved, already guarded).
    @MainActor
    @discardableResult
    func enable(port: Int) -> String? {
        guard port > 0, port <= 65535 else {
            return "Port must be between 1 and 65535"
        }
        guard !guardedPorts.contains(port) else {
            return nil
        }
        // Reserved means "warn me when threatened"; guarded means "evict
        // squatters". A port can't be both — the two would fight.
        guard !AppSettings.shared.reservedPorts.contains(port) else {
            return "Port \(port) is reserved — remove it from Reserved Ports first"
        }

        guardedPorts.append(port)
        guardedPorts.sort()
        AppSettings.shared.guardedPorts = guardedPorts

        queue.async { [weak self] in
            guard let self else { return }
            if !self.armedPorts.contains(port) {
                self.armedPorts.append(port)
                self.armedPorts.sort()
            }
            self.snapshotGrandfathers(for: [port], reason: "armed")
        }
        return nil
    }

    @MainActor
    func disable(port: Int) {
        guardedPorts.removeAll { $0 == port }
        AppSettings.shared.guardedPorts = guardedPorts

        queue.async { [weak self] in
            guard let self else { return }
            self.generation += 1
            self.armedPorts.removeAll { $0 == port }
            self.grandfatheredPids.removeValue(forKey: port)
            self.stopTimerIfDisarmed()
        }
        log.add(source: "guard", message: "Guard disarmed on port \(port)", level: .info, port: port)
    }

    @MainActor
    func isGuarded(_ port: Int) -> Bool {
        guardedPorts.contains(port)
    }

    // MARK: - Grandfather Snapshots

    /// Record the pids currently holding the given ports so the guard
    /// spares them. Snapshot must land before enforcement starts for that
    /// port — nil in `grandfatheredPids` means "hold fire".
    private func snapshotGrandfathers(for ports: [Int], reason: String) {
        let gen = generation
        Task.detached(priority: .userInitiated) { [portManager, queue] in
            var found: [Int: [Int]] = [:]
            for port in ports {
                found[port] = (try? portManager.getListeningProcesses(
                    startPort: port, endPort: port, enrich: false
                ))?.map(\.pid) ?? []
            }

            queue.async { [weak self] in
                guard let self, self.generation == gen else { return }
                for (port, pids) in found {
                    self.grandfatheredPids[port] = Set(pids)
                }
                self.startTimerIfArmed()

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    for (port, pids) in found {
                        let detail = pids.isEmpty
                            ? "port is free"
                            : "\(pids.count) current holder(s) grandfathered"
                        self.log.add(
                            source: "guard",
                            message: "Guard \(reason) on port \(port) — \(detail)",
                            level: .success,
                            port: port,
                            event: .guardAction
                        )
                    }
                }
            }
        }
    }

    // MARK: - Enforcement

    private func startTimerIfArmed() {
        guard timer == nil, !armedPorts.isEmpty else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            self?.sweep()
        }
        timer.resume()
        self.timer = timer
    }

    private func stopTimerIfDisarmed() {
        guard armedPorts.isEmpty, let timer else { return }
        timer.cancel()
        self.timer = nil
    }

    /// Queue-confined. One lsof per armed port per tick; enforcement only
    /// for ports whose grandfather snapshot has landed.
    private func sweep() {
        guard !sweepInProgress else { return }
        sweepInProgress = true
        defer { sweepInProgress = false }

        for port in armedPorts {
            guard let grandfathered = grandfatheredPids[port] else { continue }

            let holders = (try? portManager.getListeningProcesses(
                startPort: port, endPort: port, enrich: false
            )) ?? []
            let victims = PortGuardPolicy.victims(
                currentPids: holders.map(\.pid),
                grandfathered: grandfathered
            )
            guard !victims.isEmpty else { continue }

            let victimInfo = holders.filter { victims.contains($0.pid) }
            // TERM first; killProcess escalates stragglers to KILL itself.
            _ = portManager.killProcess(pids: victims, force: false)

            let evicted = victimInfo.map { (command: $0.command, pid: $0.pid) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                for process in evicted {
                    self.log.add(
                        source: "guard",
                        message: "Guard evicted \(process.command) (pid \(process.pid)) from port \(port)",
                        level: .warning,
                        port: port,
                        event: .guardAction
                    )
                    NotificationManager.shared.sendGuardEviction(
                        port: port,
                        command: process.command,
                        pid: process.pid
                    )
                }
            }
        }
    }
}
