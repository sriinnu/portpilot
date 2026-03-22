import AppKit
import SwiftUI

// MARK: - Menu Bar Panel
/// Custom NSPanel that acts as a native-feeling menu bar dropdown.
/// Uses borderless + nonactivatingPanel style so it behaves like a system menu
/// but supports full SwiftUI content including search fields.
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

        // Setup visual effect background
        let visualEffect = NSVisualEffectView(frame: contentRect)
        visualEffect.material = .menu
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true

        contentView = visualEffect
        refreshTheme()
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        close()
    }

    /// Position the panel right-aligned below a status bar button with smooth animation.
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

        // Animate in with fade + slight slide
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
    }

    /// Smoothly animate the panel out before closing.
    override func close() {
        guard !isClosing else { return }
        isClosing = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: {
            super.close()
            self.alphaValue = 1 // Reset for next show
            self.isClosing = false
        })
    }

    /// Embed a SwiftUI view inside the panel's visual effect background.
    func setSwiftUIContent<Content: View>(_ view: Content) {
        let hostingView = NSHostingView(rootView: view)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.appearance = NSApp.appearance

        guard let visualEffect = contentView as? NSVisualEffectView else { return }

        // Remove previous hosting views
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

    /// I resync the panel chrome so appearance and theme changes feel immediate.
    func refreshTheme() {
        syncAppearance()
    }

    private func syncAppearance() {
        appearance = NSApp.appearance
        guard let visualEffect = contentView as? NSVisualEffectView else { return }
        visualEffect.appearance = NSApp.appearance
        let effectiveAppearance = appearance ?? NSApp.effectiveAppearance
        visualEffect.layer?.backgroundColor = Theme.Surface.panelFill(for: effectiveAppearance).cgColor
        visualEffect.layer?.borderWidth = 1
        visualEffect.layer?.borderColor = Theme.Surface.panelBorder(for: effectiveAppearance).cgColor
    }
}
