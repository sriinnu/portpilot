import AppKit
import SwiftUI

// MARK: - Menu Bar Panel
class MenuBarPanel: NSPanel {

    private var isClosing = false
    static let arrowHeight: CGFloat = 10
    private var arrowX: CGFloat = 210
    private let outlineLayer = CAShapeLayer()
    private let pointerLayer = CAShapeLayer()
    private let silhouette = CAShapeLayer()


    /// Set by MenuBarController. A bare `close()` here used to leave the
    /// controller believing the panel was still shown — zombie refresh timer,
    /// zombie event monitor, and a dead first click on the status item after
    /// any key-steal (Cmd-Tab, clicking our own window, an alert presenting).
    /// Routing through the controller runs the full dismiss path.
    var onResignKey: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let visualEffect = NSVisualEffectView(frame: contentRect)
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 0
        visualEffect.layer?.cornerCurve = .continuous
        visualEffect.layer?.masksToBounds = true

        visualEffect.layer?.mask = silhouette
        outlineLayer.fillColor = NSColor.clear.cgColor
        visualEffect.layer?.addSublayer(pointerLayer)
        visualEffect.layer?.addSublayer(outlineLayer)
        contentView = visualEffect
        refreshTheme()
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    func showBelow(button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let buttonFrame = button.convert(button.bounds, to: nil)
        let screenFrame = buttonWindow.convertToScreen(buttonFrame)

        let panelWidth = frame.width
        let panelHeight = frame.height

        // Center below the button, clamped to screen
        let idealX = screenFrame.midX - panelWidth / 2
        let x: CGFloat
        if let screen = buttonWindow.screen ?? NSScreen.main {
            x = max(screen.visibleFrame.minX + 8, min(idealX, screen.visibleFrame.maxX - panelWidth - 8))
        } else {
            x = idealX
        }
        let y = screenFrame.minY - panelHeight
        arrowX = max(24, min(screenFrame.midX - x, panelWidth - 24))

        setFrameOrigin(NSPoint(x: x, y: y))
        refreshTheme()

        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            self.animator().alphaValue = 1
        }
    }

    override func close() {
        guard !isClosing else { return }
        isClosing = true
        NSAnimationContext.runAnimationGroup({ [weak self] context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // Use orderOut instead of super.close() to avoid weak-self limitation
            self?.orderOut(nil)
            self?.alphaValue = 1
            self?.isClosing = false
        })
    }

    func setSwiftUIContent<Content: View>(_ view: Content) {
        let hostingView = NSHostingView(rootView: view)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.appearance = NSApp.appearance

        guard let visualEffect = contentView as? NSVisualEffectView else { return }
        visualEffect.subviews.forEach { $0.removeFromSuperview() }

        visualEffect.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: Self.arrowHeight),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])
        refreshTheme()
    }

    func refreshTheme() {
        syncAppearance()
    }

    private func syncAppearance() {
        appearance = NSApp.appearance
        guard let visualEffect = contentView as? NSVisualEffectView else { return }
        visualEffect.appearance = NSApp.appearance
        let effectiveAppearance = appearance ?? NSApp.effectiveAppearance
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Use theme-aware panel fill for consistency with main window
        visualEffect.layer?.backgroundColor = Theme.Surface.panelFill(for: effectiveAppearance).cgColor

        // Theme-aware border
        visualEffect.layer?.borderWidth = 0
        visualEffect.layer?.borderColor = Theme.Surface.panelBorder(for: effectiveAppearance)
            .withAlphaComponent(isDark ? 0.30 : 0.15).cgColor

        let bounds = visualEffect.bounds
        let r = min(Theme.Liquid.panelCornerRadius, 16)
        let top = bounds.height - Self.arrowHeight
        let path = CGMutablePath()
        path.move(to: CGPoint(x: r, y: 0))
        path.addLine(to: CGPoint(x: bounds.width - r, y: 0))
        path.addQuadCurve(to: CGPoint(x: bounds.width, y: r), control: CGPoint(x: bounds.width, y: 0))
        path.addLine(to: CGPoint(x: bounds.width, y: top - r))
        path.addQuadCurve(to: CGPoint(x: bounds.width - r, y: top), control: CGPoint(x: bounds.width, y: top))
        path.addLine(to: CGPoint(x: arrowX + 10, y: top))
        path.addLine(to: CGPoint(x: arrowX, y: bounds.height))
        path.addLine(to: CGPoint(x: arrowX - 10, y: top))
        path.addLine(to: CGPoint(x: r, y: top))
        path.addQuadCurve(to: CGPoint(x: 0, y: top - r), control: CGPoint(x: 0, y: top))
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero)
        path.closeSubpath()
        let pointer = CGMutablePath()
        pointer.move(to: CGPoint(x: arrowX - 11, y: top - 1))
        pointer.addLine(to: CGPoint(x: arrowX, y: bounds.height))
        pointer.addLine(to: CGPoint(x: arrowX + 11, y: top - 1))
        pointer.closeSubpath()
        pointerLayer.path = pointer
        effectiveAppearance.performAsCurrentDrawingAppearance {
            pointerLayer.fillColor = NSColor(Theme.Surface.windowBackground).cgColor
        }
        silhouette.path = path
        outlineLayer.path = path
        outlineLayer.lineWidth = 1
        outlineLayer.strokeColor = Theme.Surface.panelBorder(for: effectiveAppearance).cgColor

        // Shadow
        visualEffect.layer?.shadowColor = NSColor.black.cgColor
        visualEffect.layer?.shadowOpacity = isDark ? 0.5 : 0.2
        visualEffect.layer?.shadowRadius = isDark ? 20 : 12
        visualEffect.layer?.shadowOffset = CGSize(width: 0, height: -4)
    }
}
