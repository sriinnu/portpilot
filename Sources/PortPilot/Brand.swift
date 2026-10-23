import SwiftUI
import AppKit

/// Typography from the offline design studies: system sans, SF Mono, and Georgia.
/// Use the local SF Mono faces when available, with a system mono fallback.
enum PortPilotTypography {
    static func font(
        direction: VisualTheme, size: CGFloat, weight: Font.Weight = .regular,
        design: Font.Design? = nil
    ) -> Font {
        if design == .serif {
            return .custom("Georgia", size: size).weight(weight)
        }
        if design == .monospaced || (design == nil && (direction == .relay || direction == .shell)) {
            let face: String
            switch weight {
            case .ultraLight, .thin, .light: face = "SFMono-Light"
            case .medium: face = "SFMono-Medium"
            case .semibold: face = "SFMono-Semibold"
            case .bold, .heavy, .black: face = "SFMono-Bold"
            default: face = "SFMono-Regular"
            }
            // Available on supported macOS versions; keep a system fallback.
            if NSFont(name: face, size: size) != nil { return .custom(face, size: size) }
            return .system(size: size, weight: weight, design: .monospaced)
        }
        return .system(size: size, weight: weight)
    }

    static func heading(direction: VisualTheme) -> Font {
        switch direction {
        case .fieldwork: return font(direction: direction, size: 32, design: .serif)
        case .relay: return font(direction: direction, size: 17, weight: .semibold)
        case .shell: return font(direction: direction, size: 27, weight: .medium)
        case .play: return font(direction: direction, size: 29, weight: .bold)
        case .orbit: return font(direction: direction, size: 35, weight: .medium)
        case .instrument, .focus: return font(direction: direction, size: 24, weight: .semibold)
        }
    }
}

/// The same 24-unit plug path used in the approved design studies and SVG assets.
struct PortPilotPlug: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 8, y: 3)); p.addLine(to: CGPoint(x: 8, y: 8))
        p.move(to: CGPoint(x: 16, y: 3)); p.addLine(to: CGPoint(x: 16, y: 8))
        p.move(to: CGPoint(x: 6, y: 8)); p.addLine(to: CGPoint(x: 18, y: 8))
        p.addLine(to: CGPoint(x: 18, y: 12))
        p.addCurve(to: CGPoint(x: 6, y: 12), control1: CGPoint(x: 18, y: 20), control2: CGPoint(x: 6, y: 20))
        p.addLine(to: CGPoint(x: 6, y: 8))
        p.move(to: CGPoint(x: 12, y: 18)); p.addLine(to: CGPoint(x: 12, y: 21))
        return p.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
            .applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}

struct PortPilotIdentity: View {
    var compact = false
    var body: some View {
        HStack(spacing: 9) {
            Text("P/").font(PortPilotTypography.font(direction: AppSettings.shared.visualTheme, size: compact ? 20 : 25, weight: .bold, design: .monospaced)).tracking(-2)
                .foregroundStyle(Theme.paletteAccent)
            if !compact { Text("PortPilot").font(PortPilotTypography.font(direction: AppSettings.shared.visualTheme, size: 16, weight: .semibold, design: AppSettings.shared.visualTheme == .fieldwork ? .serif : nil)).tracking(-0.5) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PortPilot")
    }
}

enum PortPilotBrand {
    static func menuImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setStrokeColor(NSColor.labelColor.cgColor)
            context.setLineWidth(1.6); context.setLineCap(.round); context.setLineJoin(.round)
            context.addPath(PortPilotPlug().path(in: rect.insetBy(dx: 1, dy: 1)).cgPath)
            context.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "PortPilot"
        return image
    }
}

/// Consistent support and author links in the app and menu-bar footer.
struct PortPilotFooterLinks: View {
    var onSupport: (() -> Void)?
    private let supportURL = URL(string: "https://github.com/sponsors/sriinnu")!
    private let authorURL = URL(string: "https://github.com/sriinnu")!

    var body: some View {
        HStack(spacing: 12) {
            if let onSupport {
                Button(action: onSupport) { supportLabel }.buttonStyle(.plain)
            } else {
                Link(destination: supportURL) { supportLabel }
            }
            Link("sriinnu", destination: authorURL)
                .foregroundStyle(.secondary)
                .help("sriinnu on GitHub")
        }
        .font(.system(size: 10, weight: .medium))
    }
    private var supportLabel: some View {
        Label("Support", systemImage: "heart.fill")
            .foregroundStyle(.pink)
            .help("Support PortPilot on GitHub Sponsors")
    }
}
