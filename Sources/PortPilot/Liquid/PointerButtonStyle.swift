import SwiftUI
import AppKit

// MARK: - Pointer Button Style

/// A reusable button style that swaps the cursor to a pointing hand on hover
/// and dims the label when pressed.
///
/// I keep it here so every Liquid component — pills, palette rows, donut
/// legend — reaches for the same hover/press affordance without each one
/// re-implementing the AppKit cursor dance.
struct PointerButtonStyle: ButtonStyle {
    /// Wraps the button's label with the press-dim and hover-cursor behaviour.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}
