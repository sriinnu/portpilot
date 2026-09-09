import SwiftUI
import AppKit

// MARK: - Log Entry Model

struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let source: String
    let message: String
    let level: LogLevel
    let portNumber: Int?
    /// Structured lifecycle kind — set for port/process events (bound, freed,
    /// killed, paused, resumed, guard) so the timeline renders from data
    /// instead of parsing message strings. nil for generic chatter.
    var event: LogEvent? = nil

    enum LogLevel: String {
        case info
        case success
        case warning
        case error

        var color: Color {
            switch self {
            case .info: return .primary
            case .success: return Theme.Status.connected
            case .warning: return Theme.Status.warning
            case .error: return Theme.Status.error
            }
        }
    }

    /// Lifecycle events the timeline treats as first-class.
    enum LogEvent: String, Equatable {
        case bound
        case freed
        case killed
        case paused
        case resumed
        case guardAction

        var symbol: String {
            switch self {
            case .bound: return "arrow.down.circle.fill"
            case .freed: return "arrow.up.circle.fill"
            case .killed: return "xmark.circle.fill"
            case .paused: return "pause.circle.fill"
            case .resumed: return "play.circle.fill"
            case .guardAction: return "shield.fill"
            }
        }

        var color: Color {
            switch self {
            case .bound: return Theme.Status.connected
            case .freed: return Theme.Classification.other
            case .killed: return Theme.Status.error
            case .paused: return Theme.Status.warning
            case .resumed: return Theme.Status.connected
            case .guardAction: return Theme.Action.treeView
            }
        }
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

// MARK: - Activity Log Store

/// Owns the activity log. PortViewModel relays this store's changes, and the
/// timeline surfaces read it directly — one owner, no duplicate state.
@MainActor
final class ActivityLogStore: ObservableObject {
    @Published private(set) var entries: [LogEntry] = []

    private let maxEntries = 500

    func add(source: String, message: String, level: LogEntry.LogLevel, port: Int? = nil, event: LogEntry.LogEvent? = nil) {
        entries.append(LogEntry(timestamp: Date(), source: source, message: message, level: level, portNumber: port, event: event))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func entries(for port: Int) -> [LogEntry] {
        entries.filter { $0.portNumber == port || $0.portNumber == nil }
    }

    func clear() {
        entries.removeAll()
    }

    func copyAll() {
        let text = entries.map { "\($0.formattedTime) [\($0.source)] \($0.message)" }.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
