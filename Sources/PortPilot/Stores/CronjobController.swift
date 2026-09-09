import Foundation

/// Cronjob domain pulled out of PortViewModel: discovery refresh, the run
/// controls (Run Now / Stop / pause / resume), and live run state. Errors and
/// activity-log lines are delivered through the injected handlers so the
/// controller never needs to know about the rest of the app.
@MainActor
final class CronjobController: ObservableObject {
    @Published private(set) var jobs: [CronjobEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var runHistory: [String: CronRunRecord] = [:]
    @Published private(set) var runningIDs: Set<String> = []

    private let log: ActivityLogStore
    /// Wired by the owner after init — the VM's error hook captures self,
    /// which isn't legal until every member is initialized. nil drops errors.
    var onError: ((String) -> Void)?
    private var latestRefreshID = UUID()

    init(log: ActivityLogStore) {
        self.log = log
        setupCallbacks()
    }

    // MARK: - Refresh

    func refresh() {
        isLoading = true
        let refreshID = UUID()
        latestRefreshID = refreshID

        let snapshotTask = Task.detached(priority: .userInitiated) {
            Self.loadSnapshot()
        }

        Task {
            let jobs = await snapshotTask.value
            guard latestRefreshID == refreshID else { return }
            self.jobs = jobs
            isLoading = false
            for job in jobs {
                runHistory[job.id] = CronRunManager.shared.record(for: job.id)
            }
            runningIDs = Set(jobs.map(\.id).filter { CronRunManager.shared.isRunning($0) })
        }
    }

    nonisolated private static func loadSnapshot() -> [CronjobEntry] {
        PortManager().getCronjobs()
    }

    // MARK: - Run Controls

    /// Wire up CronRunManager's callbacks so "Run Now" progress/results surface in the UI and Activity log.
    private func setupCallbacks() {
        CronRunManager.shared.onUpdate = { [weak self] jobID, record in
            DispatchQueue.main.async {
                guard let self else { return }
                self.runHistory[jobID] = record
                if record.isRunning {
                    self.runningIDs.insert(jobID)
                } else {
                    self.runningIDs.remove(jobID)
                }
            }
        }
        CronRunManager.shared.onLog = { [weak self] message, isError in
            DispatchQueue.main.async {
                self?.log.add(source: "cron", message: message, level: isError ? .error : .success)
            }
        }
    }

    /// Trigger a cronjob's command immediately, outside of its schedule.
    func runNow(_ job: CronjobEntry) {
        let started = CronRunManager.shared.runNow(job: job)
        if !started {
            log.add(source: "cron", message: "\(job.command) is already running", level: .info)
        }
    }

    /// Stop a cronjob run — whatever PortPilot started, plus a best-effort sweep for
    /// matching processes the cron daemon may have kicked off independently.
    func stop(_ job: CronjobEntry) {
        let command = job.command
        let jobID = job.id

        // Both kill paths walk process trees and TERM-wait — doing either on
        // the main actor hung the UI for up to ~3s per Stop click.
        let stopTask = Task.detached(priority: .userInitiated) {
            let stoppedTracked = CronRunManager.shared.stop(jobID: jobID)
            let killedCount = PortManager().stopRunningProcesses(matching: command)
            return (stoppedTracked, killedCount)
        }

        Task {
            let (stoppedTracked, killedCount) = await stopTask.value
            if stoppedTracked || killedCount > 0 {
                log.add(source: "cron", message: "Stopped \(command)", level: .info)
            } else {
                log.add(source: "cron", message: "\(command) is not currently running", level: .info)
            }
        }
    }

    /// Pause a user crontab entry so the cron daemon skips it until resumed.
    func pause(_ job: CronjobEntry) {
        let command = job.command

        let pauseTask = Task.detached(priority: .userInitiated) {
            try PortManager().pauseCronjob(job)
        }

        Task {
            do {
                try await pauseTask.value
                log.add(source: "cron", message: "Paused \(command)", level: .info)
                refresh()
            } catch {
                onError?(error.localizedDescription)
                log.add(source: "cron", message: "Failed to pause \(command): \(error.localizedDescription)", level: .error)
            }
        }
    }

    /// Resume a paused user crontab entry.
    func resume(_ job: CronjobEntry) {
        let command = job.command

        let resumeTask = Task.detached(priority: .userInitiated) {
            try PortManager().resumeCronjob(job)
        }

        Task {
            do {
                try await resumeTask.value
                log.add(source: "cron", message: "Started \(command)", level: .info)
                refresh()
            } catch {
                onError?(error.localizedDescription)
                log.add(source: "cron", message: "Failed to start \(command): \(error.localizedDescription)", level: .error)
            }
        }
    }
}
