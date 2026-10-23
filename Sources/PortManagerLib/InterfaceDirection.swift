import Foundation

/// Stable design identities shared by native presentation and preference migration.
public enum InterfaceDirection: String, CaseIterable, Identifiable, Sendable {
    case instrument = "Instrument", relay = "Relay", fieldwork = "Fieldwork"
    case focus = "Focus", shell = "Shell", play = "Play", orbit = "Orbit"

    public var id: String { rawValue }
    public var number: String { String(format: "%02d", Self.allCases.firstIndex(of: self)! + 1) }
    public var isDarkNative: Bool { self == .relay || self == .shell || self == .orbit }

    /// Retired palettes are migration inputs only; they never appear as choices.
    public static func restoring(_ value: String?) -> Self {
        if let value, let direction = Self(rawValue: value) { return direction }
        switch value {
        case "Sunset", "Folio": return .fieldwork
        case "Noir": return .relay
        case "Oceanic": return .focus
        case "Solarized": return .shell
        case "Sentinel": return .orbit
        default: return .instrument
        }
    }
}

/// A finite navigation language, never a system shell or a subprocess launcher.
public enum WorkspaceCommand: Equatable, Sendable {
    case help, ports, refresh, observations, schedules, clear
    case find(String), inspect(Int), invalid

    public static func parse(_ input: String) -> Self {
        let parts = input.trimmingCharacters(in: .whitespacesAndNewlines).split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let verb = parts.first else { return .help }
        let argument = parts.count == 2 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
        switch (String(verb).lowercased(), argument) {
        case ("help", ""): return .help
        case ("ports", ""), ("ls", ""): return .ports
        case ("refresh", ""): return .refresh
        case ("observations", ""), ("security", ""): return .observations
        case ("schedules", ""): return .schedules
        case ("clear", ""): return .clear
        case ("find", _) where !argument.isEmpty: return .find(argument)
        case ("inspect", _):
            guard argument.allSatisfy(\.isNumber), let port = Int(argument), (1...65535).contains(port) else { return .invalid }
            return .inspect(port)
        default: return .invalid
        }
    }
}
