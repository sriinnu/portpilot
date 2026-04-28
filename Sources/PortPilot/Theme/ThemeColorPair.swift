import SwiftUI
import AppKit

// MARK: - Theme Internals

struct ThemeColorPair {
    let light: NSColor
    let dark: NSColor

    /// I bridge the NSColor pair into a dynamic SwiftUI color.
    var color: Color {
        Color(light: light, dark: dark)
    }

    /// I resolve the concrete NSColor for the current effective appearance.
    func resolved(for appearance: NSAppearance) -> NSColor {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? dark : light
    }
}

extension NSColor {
    /// I keep surface tinting readable by falling back to the base color when blending fails.
    func blendedSafely(with color: NSColor, fraction: CGFloat) -> NSColor {
        blended(withFraction: fraction, of: color) ?? self
    }
}
