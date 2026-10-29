// Compiled with the production controller in one file by test_menubar_refresh.py.
// Private probes stay out of the shipped app; discovery and UI are production code.
import Darwin

extension MenuBarController {
    var regressionTitle: String { statusItem?.button?.title ?? "missing" }
    var regressionInterval: TimeInterval { portRefreshTimer?.timeInterval ?? -1 }
    var regressionPanelVisible: Bool { panel?.isVisible ?? false }
    var regressionTooltip: String { statusItem?.button?.toolTip ?? "" }
    func regressionDismiss() { dismissPanel() }
    func regressionResetGlance() { glanceResetDate = Date(); refreshCapsuleMetrics() }
}

private final class LoopbackFixture {
    let fd: Int32
    let port: Int
    private var closed = false

    init() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        fd = descriptor
        guard descriptor >= 0 else { throw Failure("socket") }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0, listen(descriptor, 1) == 0 else {
            Darwin.close(descriptor); throw Failure("bind/listen")
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard named == 0 else { Darwin.close(descriptor); throw Failure("getsockname") }
        port = Int(UInt16(bigEndian: address.sin_port))
    }

    func close() { if !closed { closed = true; Darwin.close(fd) } }
    deinit { close() }
}

private struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@main
@MainActor
private enum MenuBarRefreshRegression {
    private static var passed = 0

    static func check(_ condition: @autoclosure () -> Bool, _ name: String) throws {
        guard condition() else { throw Failure(name) }
        passed += 1
        print("PASS \(name)")
        fflush(stdout)
    }

    static func pump(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            _ = RunLoop.main.run(mode: .default, before: min(end, Date().addingTimeInterval(0.02)))
        }
    }

    static func wait(_ name: String, _ condition: () -> Bool) throws {
        let end = Date().addingTimeInterval(35)
        while !condition(), Date() < end { pump(0.02) }
        try check(condition(), name)
    }

    static func main() {
        do { try run() }
        catch { fputs("FAIL \(error)\n", stderr); exit(1) }
    }

    static func run() throws {
        guard let expectedHome = ProcessInfo.processInfo.environment["PORTPILOT_REGRESSION_HOME"],
              FileManager.default.homeDirectoryForCurrentUser.path == expectedHome else {
            throw Failure("refusing to run without an isolated home")
        }
        UserDefaults.standard.setVolatileDomain([
            "GuardedPorts": [Int](), "ReservedPorts": [Int](),
            "ShowNotifications": false, "BackgroundMonitoring": false,
            "AutoRefreshInterval": 1, "autoRefresh": false
        ], forName: UserDefaults.argumentDomain)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let model = PortViewModel(startThreatMonitor: false)
        try check(model.portGuard.guardedPorts.isEmpty, "Guard stays disarmed")
        try check(!model.threatMonitor.isMonitoring, "threat polling stays off")
        let notifications = NotificationManager(registerWithSystem: false)
        var controller: MenuBarController? = MenuBarController(portViewModel: model, notificationManager: notifications)
        if CommandLine.arguments.contains("--deny-discovery") {
            try wait("OS-denied discovery is reported") { !model.isLoading && model.errorMessage != nil }
            try check(model.lastRefresh == nil, "discovery failure never claims successful refresh")
            try check(model.timelineChangeCount(since: .distantPast) == 0, "discovery failure emits no lifecycle events")
            controller!.regressionResetGlance()
            try check(controller!.regressionTooltip.contains("no successful port scan yet"), "native tooltip distinguishes unavailable discovery from empty success")
            print("PASS \(passed) native discovery-failure checks")
            return
        }
        try check(PortViewModel.combinedAlertState(
            connectionCritical: false, connectionWarning: false, connectionDegraded: false,
            threatStatus: .degraded, threatSeverity: .critical
        ) == .degraded, "stale threat critical is degraded, not current")
        try check(PortViewModel.combinedAlertState(
            connectionCritical: false, connectionWarning: false, connectionDegraded: false,
            threatStatus: .paused, threatSeverity: .critical
        ) == .normal, "paused stale threat findings do not page")
        try check(PortViewModel.combinedAlertState(
            connectionCritical: false, connectionWarning: false, connectionDegraded: true,
            threatStatus: .current, threatSeverity: .critical
        ) == .critical, "current threat critical outranks connection degradation")
        try check(PortViewModel.combinedAlertState(
            connectionCritical: true, connectionWarning: false, connectionDegraded: false,
            threatStatus: .degraded, threatSeverity: .warning
        ) == .critical, "current connection critical outranks threat degradation")
        try check(PortViewModel.combinedAlertState(
            connectionCritical: false, connectionWarning: true, connectionDegraded: false,
            threatStatus: .degraded, threatSeverity: .warning
        ) == .degraded, "degradation outranks noncritical stale status")
        try wait("initial production discovery completes") { model.lastRefresh != nil && !model.isLoading }
        controller!.regressionResetGlance()
        try check(controller!.regressionTitle.isEmpty, "glance reset immediately clears badge")
        try check(!controller!.isPanelShown, "popover starts closed")

        let fixture = try LoopbackFixture()
        try wait("closed popover discovers loopback listener") { model.ports.contains { $0.port == fixture.port } && !model.isLoading }
        try wait("closed popover updates native badge") { (Int(controller!.regressionTitle) ?? 0) >= 1 }
        fixture.close()
        try wait("closed popover discovers listener release") { !model.ports.contains { $0.port == fixture.port } && !model.isLoading }
        try wait("native badge includes listener release") { (Int(controller!.regressionTitle) ?? 0) >= 2 }

        // A direct log mutation must reach AppKit well before the 5-second
        // fallback metrics timer. This catches a pre-mutation Combine read.
        controller!.regressionResetGlance()
        model.activityLog.add(source: "regression", message: "synthetic bind", level: .info, port: fixture.port, event: .bound)
        pump(0.15)
        try check((Int(controller!.regressionTitle) ?? 0) >= 1, "published change renders after mutation")

        let settings = AppSettings.shared
        settings.autoRefreshInterval = 2
        try check(controller!.regressionInterval == 2, "interval changes while closed")
        settings.autoRefreshInterval = 0
        try check(controller!.regressionInterval == 1, "invalid interval is clamped")
        settings.autoRefresh = true
        try wait("settle any scan before timer handoff") { !model.isLoading }
        let handedOff = model.lastRefresh
        pump(1.3)
        try check(model.lastRefresh == handedOff, "menu timer yields to app-wide auto-refresh")
        let delegate = AppDelegate(viewModel: model)
        delegate.regressionObserveRefreshSettings()
        settings.refreshInterval = 1
        try check(delegate.regressionAutoRefreshInterval == 1, "app timer observes interval changes")
        try wait("app-wide timer completes production discovery") {
            model.lastRefresh != handedOff && !model.isLoading && !model.isLoadingAllConnections
        }
        settings.refreshInterval = 0
        try check(delegate.regressionAutoRefreshInterval == 1, "app-wide timer clamps invalid interval")
        settings.autoRefresh = false
        try check(delegate.regressionAutoRefreshInterval == nil, "disabling auto-refresh removes app timer")
        let resumedDate = model.lastRefresh
        try wait("menu polling resumes after auto-refresh disabled") { model.lastRefresh != resumedDate && !model.isLoading }
        delegate.regressionStopRefreshObservation()

        // Busy discovery must not be replaced by a background request.
        settings.autoRefresh = true
        let busyDate = model.lastRefresh
        model.isLoading = true
        model.isLoadingAllConnections = true
        model.refreshInBackground(includeConnections: true)
        pump(0.1)
        try check(model.isLoading && model.isLoadingAllConnections && model.lastRefresh == busyDate, "busy snapshots are not superseded")
        model.isLoading = false
        model.isLoadingAllConnections = false

        let oldDate = model.lastRefresh
        let oldCount = model.totalCount
        let oldChanges = model.timelineChangeCount(since: .distantPast)
        model.portRangeStart = "-1"
        model.refreshPorts()
        try check(model.errorMessage != nil && !model.isLoading, "invalid scan is reported")
        try check(model.lastRefresh == oldDate && model.totalCount == oldCount, "failed scan preserves successful snapshot")
        try check(model.timelineChangeCount(since: .distantPast) == oldChanges, "failed scan does not advance timeline")
        model.portRangeStart = ""

        let first = try LoopbackFixture()
        let second = try LoopbackFixture()
        defer { first.close(); second.close() }
        model.refreshPorts()
        try wait("full snapshot contains both range fixtures") { !model.isLoading && model.ports.contains { $0.port == first.port } && model.ports.contains { $0.port == second.port } }
        let rangeStart = Date()
        model.portRangeStart = String(first.port)
        model.portRangeEnd = String(first.port)
        model.refreshPorts()
        try wait("range-limited scan completes") { !model.isLoading }
        model.portRangeStart = ""
        model.portRangeEnd = ""
        model.refreshPorts()
        try wait("full scan after range completes") { !model.isLoading }
        try check(!model.logs.contains { $0.timestamp > rangeStart && $0.portNumber == second.port && ($0.event == .bound || $0.event == .freed) }, "range view never invents lifecycle events")

        controller!.showPopover()
        try check(controller!.isPanelShown, "native popover opens")
        try check(controller!.regressionPanelVisible, "native panel is visible in AppKit")
        try check(controller!.regressionTitle.isEmpty, "opening popover clears badge synchronously")
        controller!.regressionDismiss()
        try check(!controller!.isPanelShown, "native popover closes")
        try wait("popover-triggered scan settles") { !model.isLoading && !model.isLoadingAllConnections }
        settings.autoRefresh = false
        let closedDate = model.lastRefresh
        try wait("polling survives open-close lifecycle") { model.lastRefresh != closedDate && !model.isLoading }

        // A corrupt alert-list must degrade the main connection snapshot,
        // preserve the last good data, and recover only after a checked read.
        guard let successfulConnectionDate = model.lastSuccessfulAllConnectionsRefresh else {
            throw Failure("connection refresh never completed successfully")
        }
        let successfulConnectionCount = model.allConnections.count
        let connectionMetrics = LiveMetricsHistory()
        connectionMetrics.start(viewModel: model)
        let successfulMetricSamples = connectionMetrics.connections.count
        let policyDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".portpilot")
        try FileManager.default.createDirectory(at: policyDirectory, withIntermediateDirectories: true)
        let policyURL = policyDirectory.appendingPathComponent("blocklist.txt")
        try Data([0xff]).write(to: policyURL)
        model.refreshAllConnections()
        try wait("corrupt alert-list degrades connection refresh") {
            !model.isLoadingAllConnections && model.allConnectionsError != nil
        }
        try check(model.lastSuccessfulAllConnectionsRefresh == successfulConnectionDate, "failed connection refresh keeps last-success time")
        try check(model.allConnections.count == successfulConnectionCount, "failed connection refresh keeps last-good observations")
        try check(model.alertState == .degraded, "failed connection refresh propagates degraded status")
        pump(0.1)
        try check(controller!.regressionTooltip.contains("connection scan incomplete"), "menubar tooltip reports degraded connections")
        pump(2.2)
        try check(connectionMetrics.connections.count == successfulMetricSamples, "degraded connection data does not enter metric history")
        try FileManager.default.removeItem(at: policyURL)
        model.refreshAllConnections()
        try wait("connection refresh recovers after policy read succeeds") {
            !model.isLoadingAllConnections && model.allConnectionsError == nil &&
                model.lastSuccessfulAllConnectionsRefresh != successfulConnectionDate
        }
        pump(2.2)
        try check(connectionMetrics.connections.count > successfulMetricSamples, "connection metric sampling resumes after recovery")
        connectionMetrics.stop()

        weak var released = controller
        controller = nil
        pump(0.1)
        try check(released == nil, "controller releases without timer/subscription cycle")
        let stoppedDate = model.lastRefresh
        pump(1.3)
        try check(model.lastRefresh == stoppedDate, "controller teardown stops background discovery")
        print("PASS \(passed) native regression checks; no real services modified")
    }
}
