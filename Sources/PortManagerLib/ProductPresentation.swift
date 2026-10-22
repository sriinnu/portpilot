import Foundation

/// Shared, side-effect-free wording for monitoring chrome. Freshness and
/// severity are separate: an absent finding never makes a paused scan current.
public struct MonitoringPresentation: Equatable, Sendable {
    public let status: ThreatMonitoringStatus
    public let highestSeverity: ThreatSeverity?
    public let pollInterval: TimeInterval

    public init(status: ThreatMonitoringStatus, highestSeverity: ThreatSeverity?, pollInterval: TimeInterval) {
        self.status = status
        self.highestSeverity = highestSeverity
        self.pollInterval = pollInterval
    }

    public var headline: String {
        switch status {
        case .paused: return "Threat monitoring paused"
        case .pending: return "Waiting for first threat check"
        case .degraded: return "Threat monitoring degraded"
        case .current:
            switch highestSeverity {
            case .critical: return "Critical findings to review"
            case .warning: return "Findings need review"
            case .info: return "Informational findings to review"
            case nil: return "No findings in latest check"
            }
        }
    }

    public var compactLabel: String {
        switch status {
        case .paused: return "Threat monitor paused"
        case .pending: return "Threat check pending"
        case .degraded: return "Threat monitor degraded"
        case .current: return "Threat monitor active"
        }
    }

    public var cadenceLabel: String {
        switch status {
        case .paused: return "Checks paused"
        case .pending: return "Awaiting successful check"
        case .degraded: return "Last result may be stale"
        case .current:
            guard pollInterval.isFinite, pollInterval > 0 else { return "Threat check interval unavailable" }
            return String(format: "Threat checks every %.0fs", pollInterval)
        }
    }
}

/// Routing only; frontends decide how to present the destination.
public enum NotificationReviewDestination: Equatable, Sendable {
    case security

    public static let openSecurityAction = "OPEN_SECURITY_ACTION"
    public static let threatCategory = "THREAT_ALERT"

    public static func resolve(categoryIdentifier: String, actionIdentifier: String, isDefaultAction: Bool) -> Self? {
        let reviewCategory = categoryIdentifier == threatCategory || categoryIdentifier == "CONNECTION_ALERT"
        guard reviewCategory else { return nil }
        if isDefaultAction || actionIdentifier == openSecurityAction || actionIdentifier == "VIEW_CONNECTIONS_ACTION" {
            return .security
        }
        return nil
    }
}

public enum LoginItemStatus: Equatable, Sendable {
    case enabled, disabled, requiresApproval, unavailable

    public var toggleValue: Bool { self == .enabled || self == .requiresApproval }

    public var detail: String {
        switch self {
        case .enabled: return "Enabled in macOS Login Items."
        case .disabled: return "Launch at login is off."
        case .requiresApproval: return "Waiting for approval in macOS Login Items."
        case .unavailable: return "macOS cannot find this app's login item. Check the installed app."
        }
    }
}

public protocol LoginItemService {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

/// Always reports the service's actual state after the request, including an
/// unchanged state after failure. No requested Boolean is treated as success.
public struct LoginItemChangeResult: Equatable, Sendable {
    public let status: LoginItemStatus
    public let errorMessage: String?

    public static func apply(enabled: Bool, service: any LoginItemService) -> Self {
        var errorMessage: String?
        do {
            if enabled {
                if service.status != .enabled && service.status != .requiresApproval { try service.register() }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        return Self(status: service.status, errorMessage: errorMessage)
    }
}

extension ProcessTerminationOutcome {
    public var userFacingDescription: String {
        switch self {
        case .terminated: return "Process exited"
        case .alreadyExited: return "Process had already exited"
        case .invalidPID: return "Invalid or protected process ID"
        case .permissionDenied: return "Permission denied"
        case .identityUnavailable: return "Process identity unavailable; refresh before trying again"
        case .identityMismatch: return "PID now belongs to a different process; refresh before trying again"
        case .signalFailed(let code): return "Signal failed (errno \(code))"
        case .probeFailed(let code): return "Process status unavailable (errno \(code))"
        case .survived: return "Process still running after termination attempt"
        case .cancelled: return "Termination cancelled before further signals"
        }
    }
}
