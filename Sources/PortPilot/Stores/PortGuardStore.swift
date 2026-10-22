import Foundation

/// Port guard: armed enforcement over specific ports. Whatever holds a
/// port when the guard is armed is grandfathered and left alone; anything
/// that binds it afterwards gets TERM'd (escalating to KILL) and logged
/// loudly.
///
/// Enforcement is a process-incarnation sweep, not a state-change listener: a
/// squatter that replaces a dying holder between two ticks never shows a
/// free→occupied transition, but the pid diff still catches it. The sweep
/// runs on a private utility queue on the store's own timer — armed
/// whenever guards exist, regardless of the background-monitoring toggle.
///
/// Confinement: `guardedPorts` is @Published and main-confined (UI reads
/// and enables/disables happen on main); enforcement state is queue-confined.
/// `@unchecked Sendable` is justified by explicit confinement: published UI
/// state and callbacks are touched on MainActor, enforcement state only on
/// `queue`, and PortManager's sole mutable cache is protected by its lock.
/// The revocation gate owns an NSLock for its main-actor/queue shared state.
final class PortGuardStore: ObservableObject, @unchecked Sendable {
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
    /// Queue-confined generations corresponding to the current baselines.
    private var armedGenerations: [Int: UUID] = [:]
    private let enforcementGate = PortGuardEnforcementGate()
    /// Queue-confined. Key present = a complete identity snapshot landed
    /// ([] = port was free); key absent = enforcement holds fire.
    private var baselineState = PortGuardBaselineState()

    init(log: ActivityLogStore) {
        self.log = log

        // Persisted guards survive relaunch — but pids don't. Whatever holds
        // the guarded ports right now gets grandfathered so launching
        // PortPilot never turns into a surprise massacre.
        let ports = Array(Set(AppSettings.shared.guardedPorts)).sorted()
        guardedPorts = ports
        let generations = Dictionary(uniqueKeysWithValues: ports.map {
            ($0, enforcementGate.activate(port: $0))
        })
        queue.async { [weak self] in
            guard let self else { return }
            for port in ports {
                guard let enforcementGeneration = generations[port],
                      self.enforcementGate.permits(port: port, generation: enforcementGeneration) else { continue }
                self.armedPorts.append(port)
                self.armedGenerations[port] = enforcementGeneration
                let generation = self.baselineState.beginSnapshot(port: port)
                self.snapshotGrandfather(for: port, generation: generation, enforcementGeneration: enforcementGeneration, reason: "restored")
            }
            self.startTimerIfArmed()
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

        let enforcementGeneration = enforcementGate.activate(port: port)
        guardedPorts.append(port)
        guardedPorts.sort()
        AppSettings.shared.guardedPorts = guardedPorts

        queue.async { [weak self] in
            guard let self else { return }
            guard self.enforcementGate.permits(port: port, generation: enforcementGeneration) else { return }
            if !self.armedPorts.contains(port) {
                self.armedPorts.append(port)
                self.armedPorts.sort()
            }
            self.armedGenerations[port] = enforcementGeneration
            let generation = self.baselineState.beginSnapshot(port: port)
            self.snapshotGrandfather(for: port, generation: generation, enforcementGeneration: enforcementGeneration, reason: "armed")
            self.startTimerIfArmed()
        }
        return nil
    }

    @MainActor
    func disable(port: Int) {
        // Revoke before publishing/persisting or queueing cleanup. The queue
        // may be inside a termination wait; its next signal must fail the gate.
        enforcementGate.invalidate(port: port)
        guardedPorts.removeAll { $0 == port }
        AppSettings.shared.guardedPorts = guardedPorts

        queue.async { [weak self] in
            guard let self else { return }
            self.baselineState.disable(port: port)
            self.armedGenerations.removeValue(forKey: port)
            self.armedPorts.removeAll { $0 == port }
            self.stopTimerIfDisarmed()
        }
        log.add(source: "guard", message: "Guard disarmed on port \(port)", level: .info, port: port)
    }

    @MainActor
    func isGuarded(_ port: Int) -> Bool {
        guardedPorts.contains(port)
    }

    // MARK: - Grandfather Snapshots

    /// Capture a complete fingerprint snapshot. Discovery errors and holders
    /// without kernel incarnation tokens leave the port unarmed; they are never
    /// converted into an empty "port was free" baseline.
    private func snapshotGrandfather(for port: Int, generation: UInt64, enforcementGeneration: UUID, reason: String) {
        Task.detached(priority: .userInitiated) { [weak self, portManager, queue] in
            let result: Result<[ProcessIdentity], Error>
            do {
                let identities = try portManager.getStableListeningProcessIdentities(port: port)
                result = .success(identities)
            } catch {
                result = .failure(error)
            }

            queue.async { [weak self] in
                guard let self else { return }
                guard self.enforcementGate.permits(port: port, generation: enforcementGeneration),
                      self.armedGenerations[port] == enforcementGeneration else { return }

                switch result {
                case .success(let identities):
                    guard self.baselineState.completeSnapshot(
                        port: port,
                        generation: generation,
                        identities: identities
                    ) else { return }
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        guard self.enforcementGate.permits(port: port, generation: enforcementGeneration) else { return }
                        let detail = identities.isEmpty
                            ? "port is free"
                            : "\(identities.count) current holder(s) grandfathered"
                        self.log.add(
                            source: "guard",
                            message: "Guard \(reason) on port \(port) — \(detail)",
                            level: .success,
                            port: port,
                            event: .guardAction
                        )
                    }
                case .failure(let error):
                    guard self.baselineState.completeSnapshot(
                        port: port,
                        generation: generation,
                        identities: nil
                    ) else { return }
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        guard self.enforcementGate.permits(port: port, generation: enforcementGeneration) else { return }
                        let message = "Guard on port \(port) is waiting for a complete process snapshot: \(error.localizedDescription)"
                        self.log.add(source: "guard", message: message, level: .error, port: port)
                        self.onError?(message)
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
            guard let enforcementGeneration = armedGenerations[port],
                  enforcementGate.permits(port: port, generation: enforcementGeneration) else { continue }
            guard let grandfathered = baselineState.baseline(for: port) else {
                if !baselineState.isSnapshotInFlight(for: port) {
                    let generation = baselineState.beginSnapshot(port: port)
                    snapshotGrandfather(for: port, generation: generation, enforcementGeneration: enforcementGeneration, reason: "retry")
                }
                continue
            }

            let holders: [PortProcess]
            do {
                holders = try portManager.getListeningProcesses(
                    startPort: port, endPort: port, enrich: true
                )
            } catch {
                reportSweepFailure(port: port, generation: enforcementGeneration, detail: "discovery failed: \(error.localizedDescription)")
                continue
            }
            let current = holders.compactMap(ProcessIdentity.init(process:))
            guard current.count == holders.count else {
                reportSweepFailure(port: port, generation: enforcementGeneration, detail: "a current holder could not be fingerprinted")
                continue
            }
            let victims = PortGuardPolicy.victims(
                current: current,
                grandfathered: grandfathered
            )
            guard !victims.isEmpty else { continue }

            let victimPIDs = Set(victims.map(\.pid))
            let victimInfo = holders.filter { victimPIDs.contains($0.pid) }
            // TERM first; the typed API escalates confirmed same-incarnation stragglers.
            let gate = enforcementGate
            let result = portManager.terminateProcesses(identities: victims, force: false) {
                gate.permits(port: port, generation: enforcementGeneration)
            }

            let evicted = victimInfo
                .filter { result.terminated.contains($0.pid) }
                .map { (command: $0.command, pid: $0.pid) }
            let cancelled = result.cancelled
            let unresolved = result.unresolved.filter { !cancelled.contains($0) }
            let departed = result.alreadyExited
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
                if !departed.isEmpty {
                    self.log.add(
                        source: "guard",
                        message: "Guard found pid(s) \(departed.map(String.init).joined(separator: ", ")) already gone from port \(port)",
                        level: .info,
                        port: port,
                        event: .guardAction
                    )
                }
                if !cancelled.isEmpty {
                    self.log.add(
                        source: "guard",
                        message: "Guard enforcement cancelled for pid(s) \(cancelled.map(String.init).joined(separator: ", ")) on port \(port) after the guard changed",
                        level: .info,
                        port: port,
                        event: .guardAction
                    )
                }
                if !unresolved.isEmpty {
                    let message = "Guard could not confirm eviction of pid(s) \(unresolved.map(String.init).joined(separator: ", ")) from port \(port)"
                    self.log.add(source: "guard", message: message, level: .error, port: port)
                    self.onError?(message)
                }
            }
        }
    }

    private func reportSweepFailure(port: Int, generation: UUID, detail: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.enforcementGate.permits(port: port, generation: generation) else { return }
            let message = "Guard skipped port \(port): \(detail)"
            self.log.add(source: "guard", message: message, level: .error, port: port)
            self.onError?(message)
        }
    }
}
