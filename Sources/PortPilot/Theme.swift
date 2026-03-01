import SwiftUI
import AppKit

// MARK: - Adaptive Color Extension

extension Color {
    /// Create an adaptive color that automatically adjusts for light/dark mode
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? dark : light
        }))
    }
}

// MARK: - Theme

enum Theme {

    // MARK: - Section Colors (per ConnectionType)

    enum Section {
        static let cloudflare = Color(
            light: NSColor(red: 0.90, green: 0.50, blue: 0.10, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.65, blue: 0.30, alpha: 1)
        )
        static let kubernetes = Color(
            light: NSColor(red: 0.15, green: 0.60, blue: 0.65, alpha: 1),
            dark: NSColor(red: 0.30, green: 0.78, blue: 0.82, alpha: 1)
        )
        static let local = Color(
            light: NSColor(red: 0.20, green: 0.68, blue: 0.30, alpha: 1),
            dark: NSColor(red: 0.35, green: 0.82, blue: 0.45, alpha: 1)
        )
        static let ssh = Color(
            light: NSColor(red: 0.55, green: 0.30, blue: 0.75, alpha: 1),
            dark: NSColor(red: 0.72, green: 0.50, blue: 0.90, alpha: 1)
        )
    }

    // MARK: - Status Colors

    enum Status {
        static let connected = Color(
            light: NSColor(red: 0.20, green: 0.70, blue: 0.30, alpha: 1),
            dark: NSColor(red: 0.35, green: 0.85, blue: 0.45, alpha: 1)
        )
        static let error = Color(
            light: NSColor(red: 0.85, green: 0.20, blue: 0.20, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.40, blue: 0.40, alpha: 1)
        )
        static let warning = Color(
            light: NSColor(red: 0.90, green: 0.55, blue: 0.10, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.70, blue: 0.30, alpha: 1)
        )
    }

    // MARK: - Action Colors

    enum Action {
        static let refresh = Color(
            light: NSColor(red: 0.20, green: 0.68, blue: 0.30, alpha: 1),
            dark: NSColor(red: 0.35, green: 0.82, blue: 0.45, alpha: 1)
        )
        static let kill = Color(
            light: NSColor(red: 0.85, green: 0.20, blue: 0.20, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.40, blue: 0.40, alpha: 1)
        )
        static let sponsors = Color(
            light: NSColor(red: 0.85, green: 0.30, blue: 0.55, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.50, blue: 0.70, alpha: 1)
        )
        static let add = Color(
            light: NSColor(red: 0.20, green: 0.68, blue: 0.30, alpha: 1),
            dark: NSColor(red: 0.35, green: 0.82, blue: 0.45, alpha: 1)
        )
        static let importAction = Color(
            light: NSColor.controlAccentColor,
            dark: NSColor(red: 0.40, green: 0.60, blue: 1.00, alpha: 1)
        )
        static let treeView = Color(
            light: NSColor(red: 0.20, green: 0.45, blue: 0.85, alpha: 1),
            dark: NSColor(red: 0.40, green: 0.65, blue: 1.00, alpha: 1)
        )
    }

    // MARK: - Badge Colors

    enum Badge {
        static let accentBackground = Color(
            light: NSColor(red: 0.20, green: 0.45, blue: 0.90, alpha: 1),
            dark: NSColor(red: 0.35, green: 0.55, blue: 1.00, alpha: 1)
        )
        static let accentText = Color.white
        static let connectedBackground = Color(
            light: NSColor(red: 0.20, green: 0.70, blue: 0.30, alpha: 0.15),
            dark: NSColor(red: 0.35, green: 0.85, blue: 0.45, alpha: 0.20)
        )
        static let connectedText = Color(
            light: NSColor(red: 0.15, green: 0.60, blue: 0.25, alpha: 1),
            dark: NSColor(red: 0.35, green: 0.85, blue: 0.45, alpha: 1)
        )
    }

    // MARK: - Log Source Colors

    enum LogSource {
        static func color(for source: String) -> Color {
            switch source.lowercased() {
            case "kubectl": return Color(
                light: NSColor(red: 0.20, green: 0.45, blue: 0.85, alpha: 1),
                dark: NSColor(red: 0.45, green: 0.65, blue: 1.00, alpha: 1)
            )
            case "socat": return Color(
                light: NSColor(red: 0.85, green: 0.50, blue: 0.10, alpha: 1),
                dark: NSColor(red: 1.00, green: 0.65, blue: 0.30, alpha: 1)
            )
            case "kill": return Color(
                light: NSColor(red: 0.85, green: 0.20, blue: 0.20, alpha: 1),
                dark: NSColor(red: 1.00, green: 0.40, blue: 0.40, alpha: 1)
            )
            default: return Color(
                light: NSColor(red: 0.50, green: 0.50, blue: 0.55, alpha: 1),
                dark: NSColor(red: 0.65, green: 0.65, blue: 0.70, alpha: 1)
            )
            }
        }

        static func backgroundColor(for source: String) -> Color {
            switch source.lowercased() {
            case "kubectl": return Color(
                light: NSColor(red: 0.20, green: 0.45, blue: 0.85, alpha: 0.12),
                dark: NSColor(red: 0.45, green: 0.65, blue: 1.00, alpha: 0.18)
            )
            case "socat": return Color(
                light: NSColor(red: 0.85, green: 0.50, blue: 0.10, alpha: 0.12),
                dark: NSColor(red: 1.00, green: 0.65, blue: 0.30, alpha: 0.18)
            )
            case "kill": return Color(
                light: NSColor(red: 0.85, green: 0.20, blue: 0.20, alpha: 0.12),
                dark: NSColor(red: 1.00, green: 0.40, blue: 0.40, alpha: 0.18)
            )
            default: return Color(
                light: NSColor(red: 0.50, green: 0.50, blue: 0.55, alpha: 0.10),
                dark: NSColor(red: 0.65, green: 0.65, blue: 0.70, alpha: 0.15)
            )
            }
        }
    }

    // MARK: - Surface Colors (auto-adapt via system NSColors)

    enum Surface {
        static let controlBackground = Color(nsColor: .controlBackgroundColor)
        static let windowBackground = Color(nsColor: .windowBackgroundColor)
        static let hover = Color(nsColor: .selectedContentBackgroundColor).opacity(0.12)
        static let selected = Color.accentColor.opacity(0.15)
    }

    // MARK: - SF Symbol Constants

    enum Icon {
        // Connection types
        static let local = "desktopcomputer"
        static let kubernetes = "cube.fill"
        static let cloudflare = "cloud.fill"
        static let ssh = "terminal.fill"

        // Actions
        static let refresh = "arrow.clockwise"
        static let kill = "stop.fill"
        static let killAll = "xmark.circle.fill"
        static let add = "plus"
        static let importFile = "square.and.arrow.down"
        static let copy = "doc.on.doc"
        static let trash = "trash.fill"
        static let settings = "gearshape"
        static let quit = "power"
        static let openWindow = "macwindow"
        static let sponsors = "heart.fill"
        static let treeView = "list.bullet.indent"

        // Status
        static let connected = "antenna.radiowaves.left.and.right"
        static let globe = "globe.americas.fill"
        static let notification = "bell.fill"
        static let notificationOff = "bell.slash"
        static let checkmark = "checkmark.circle.fill"

        // Config field icons
        static let name = "link.circle"
        static let type = "display"
        static let process = "terminal"
        static let pid = "number"
        static let user = "person"

        // Options icons
        static let autoReconnect = "arrow.clockwise"
        static let enabled = "checkmark.circle"
        static let notifyConnect = "bell.fill"
        static let notifyDisconnect = "bell.slash"

        // Port mapping
        static let portArrow = "arrow.left.arrow.right"

        // Search / nav
        static let search = "magnifyingglass"
        static let clearSearch = "xmark.circle.fill"
        static let chevronDown = "chevron.down"
        static let chevronRight = "chevron.right"

        // App logo
        static let appLogo = "network"
    }

    // MARK: - Config Field Icon Colors

    enum ConfigIcon {
        static let name = Color(
            light: NSColor(red: 0.20, green: 0.45, blue: 0.85, alpha: 1),
            dark: NSColor(red: 0.40, green: 0.65, blue: 1.00, alpha: 1)
        )
        static let type = Color(
            light: NSColor(red: 0.20, green: 0.68, blue: 0.30, alpha: 1),
            dark: NSColor(red: 0.35, green: 0.82, blue: 0.45, alpha: 1)
        )
        static let process = Color(
            light: NSColor(red: 0.15, green: 0.60, blue: 0.65, alpha: 1),
            dark: NSColor(red: 0.30, green: 0.78, blue: 0.82, alpha: 1)
        )
        static let pid = Color(
            light: NSColor(red: 0.50, green: 0.50, blue: 0.55, alpha: 1),
            dark: NSColor(red: 0.65, green: 0.65, blue: 0.70, alpha: 1)
        )
        static let user = Color(
            light: NSColor(red: 0.55, green: 0.30, blue: 0.75, alpha: 1),
            dark: NSColor(red: 0.72, green: 0.50, blue: 0.90, alpha: 1)
        )
    }

    // MARK: - Option Toggle Icon Colors

    enum OptionIcon {
        static let autoReconnect = Color(
            light: NSColor(red: 0.15, green: 0.60, blue: 0.65, alpha: 1),
            dark: NSColor(red: 0.30, green: 0.78, blue: 0.82, alpha: 1)
        )
        static let enabled = Color(
            light: NSColor(red: 0.20, green: 0.68, blue: 0.30, alpha: 1),
            dark: NSColor(red: 0.35, green: 0.82, blue: 0.45, alpha: 1)
        )
        static let notifyConnect = Color(
            light: NSColor(red: 0.90, green: 0.55, blue: 0.10, alpha: 1),
            dark: NSColor(red: 1.00, green: 0.70, blue: 0.30, alpha: 1)
        )
        static let notifyDisconnect = Color(
            light: NSColor(red: 0.50, green: 0.50, blue: 0.55, alpha: 1),
            dark: NSColor(red: 0.65, green: 0.65, blue: 0.70, alpha: 1)
        )
    }

    // MARK: - Port Mapping Colors

    enum PortMapping {
        static let localStroke = Color(
            light: NSColor(red: 0.20, green: 0.45, blue: 0.85, alpha: 0.5),
            dark: NSColor(red: 0.40, green: 0.65, blue: 1.00, alpha: 0.5)
        )
        static let localFill = Color(
            light: NSColor(red: 0.20, green: 0.45, blue: 0.85, alpha: 0.08),
            dark: NSColor(red: 0.40, green: 0.65, blue: 1.00, alpha: 0.12)
        )
        static let protocolStroke = Color(
            light: NSColor(red: 0.85, green: 0.50, blue: 0.10, alpha: 0.5),
            dark: NSColor(red: 1.00, green: 0.65, blue: 0.30, alpha: 0.5)
        )
        static let protocolFill = Color(
            light: NSColor(red: 0.85, green: 0.50, blue: 0.10, alpha: 0.08),
            dark: NSColor(red: 1.00, green: 0.65, blue: 0.30, alpha: 0.12)
        )
        static let remoteStroke = Color(
            light: NSColor(red: 0.20, green: 0.68, blue: 0.30, alpha: 0.5),
            dark: NSColor(red: 0.35, green: 0.82, blue: 0.45, alpha: 0.5)
        )
        static let remoteFill = Color(
            light: NSColor(red: 0.20, green: 0.68, blue: 0.30, alpha: 0.08),
            dark: NSColor(red: 0.35, green: 0.82, blue: 0.45, alpha: 0.12)
        )
    }

    // MARK: - Size Constants

    enum Size {
        static let statusDotLarge: CGFloat = 8
        static let statusDotSmall: CGFloat = 6
        static let cornerRadius: CGFloat = 6
        static let cornerRadiusSmall: CGFloat = 4
        static let sectionIconSize: CGFloat = 14
        static let actionIconSize: CGFloat = 12
        static let badgeIconSize: CGFloat = 11
    }
}
