import AppKit
import SwiftUI

// MARK: - Menu Bar Panel
class MenuBarPanel: NSPanel {

    private var isClosing = false

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
        visualEffect.layer?.cornerRadius = 16
        visualEffect.layer?.cornerCurve = .continuous
        visualEffect.layer?.masksToBounds = true

        contentView = visualEffect
        refreshTheme()
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        close()
    }

    func showBelow(button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let buttonFrame = button.convert(button.bounds, to: nil)
        let screenFrame = buttonWindow.convertToScreen(buttonFrame)

        let panelWidth = frame.width
        let panelHeight = frame.height

        let x = screenFrame.maxX - panelWidth
        let y = screenFrame.minY - panelHeight - 4

        setFrameOrigin(NSPoint(x: x, y: y))
        refreshTheme()

        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            self.animator().alphaValue = 1
        }
    }

    override func close() {
        guard !isClosing else { return }
        isClosing = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: {
            super.close()
            self.alphaValue = 1
            self.isClosing = false
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
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
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
        visualEffect.layer?.backgroundColor = Theme.Surface.panelFill(for: effectiveAppearance).cgColor
        visualEffect.layer?.borderWidth = 0.5
        visualEffect.layer?.borderColor = Theme.Surface.panelBorder(for: effectiveAppearance)
            .withAlphaComponent(0.3).cgColor
    }
}
