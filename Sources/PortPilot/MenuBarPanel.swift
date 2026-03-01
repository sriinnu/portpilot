import AppKit
import SwiftUI

// MARK: - Menu Bar Panel
/// Custom NSPanel that acts as a native-feeling menu bar dropdown.
/// Uses borderless + nonactivatingPanel style so it behaves like a system menu
/// but supports full SwiftUI content including search fields.
class MenuBarPanel: NSPanel {

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
        visualEffect.layer?.cornerRadius = 10
        visualEffect.layer?.masksToBounds = true

        contentView = visualEffect
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        close()
    }

    /// Position the panel right-aligned below a status bar button.
    func showBelow(button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let buttonFrame = button.convert(button.bounds, to: nil)
        let screenFrame = buttonWindow.convertToScreen(buttonFrame)

        let panelWidth = frame.width
        let panelHeight = frame.height

        let x = screenFrame.maxX - panelWidth
        let y = screenFrame.minY - panelHeight - 4

        setFrameOrigin(NSPoint(x: x, y: y))
        makeKeyAndOrderFront(nil)
    }

    /// Embed a SwiftUI view inside the panel's visual effect background.
    func setSwiftUIContent<Content: View>(_ view: Content) {
        let hostingView = NSHostingView(rootView: view)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

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
    }
}
