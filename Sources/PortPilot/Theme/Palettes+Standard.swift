import SwiftUI
import AppKit

extension ThemeColorPair {
    static func hex(_ light: UInt32, _ dark: UInt32? = nil) -> Self {
        func color(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
        return Self(light: color(light), dark: color(dark ?? light))
    }
}

extension ThemePalette {
    static func direction(_ direction: InterfaceDirection) -> ThemePalette {
        let accent: ThemeColorPair
        let window: ThemeColorPair
        let surface: ThemeColorPair
        let chrome: ThemeColorPair
        switch direction {
        case .instrument:
            accent = .hex(0x5555C8, 0xA5A4FF); window = .hex(0xF6F7F9, 0x191B22)
            surface = .hex(0xFFFFFF, 0x22252E); chrome = .hex(0xECEEF2, 0x1D2028)
        case .relay:
            accent = .hex(0xD4ED9A); window = .hex(0x151916)
            surface = .hex(0x1C221C); chrome = .hex(0x20271F)
        case .fieldwork:
            accent = .hex(0x446746, 0xB3CF9B); window = .hex(0xF5F1E7, 0x25271F)
            surface = .hex(0xFFFCF3, 0x2C3026); chrome = .hex(0xEBE7DA, 0x20241D)
        case .focus:
            accent = .hex(0x386EC7, 0x9DBEFF); window = .hex(0xF2F6FC, 0x19222F)
            surface = .hex(0xFFFFFF, 0x222D3D); chrome = .hex(0xE8EFF9, 0x1C2837)
        case .shell:
            accent = .hex(0x9AE7C3); window = .hex(0x101719)
            surface = .hex(0x182426); chrome = .hex(0x1C2528)
        case .play:
            accent = .hex(0x4545C7, 0xB5B1FF); window = .hex(0xFAF7EF, 0x252332)
            surface = .hex(0xFFFDF8, 0x302D40); chrome = .hex(0xF2EFE7, 0x211F2D)
        case .orbit:
            accent = .hex(0xE5AE82); window = .hex(0x141719)
            surface = .hex(0x222828); chrome = .hex(0x191D20)
        }
        // Status and action semantics stay recognizable across every direction.
        return ThemePalette(
            window: window, surface: surface, chrome: chrome,
            cloudflare: .hex(0xB6601C, 0xF0B376), kubernetes: .hex(0x386DB2, 0x90BAF2),
            local: accent, database: .hex(0x8D6631, 0xD8BB85), ssh: .hex(0x7855AD, 0xC1A8EB),
            orbstack: .hex(0x366CA8, 0x91BDEE), proxy: .hex(0x7855AD, 0xC1A8EB),
            connected: .hex(0x2E7541, 0x9ECFA8), connectedBackground: .hex(0xE5F2E7, 0x243C2A),
            error: .hex(0xB72E36, 0xFFA8A5), warning: .hex(0x8C600D, 0xF3C77F), accent: accent,
            onAccent: direction.isDarkNative ? .hex(0x17231B) : .hex(0xFFFFFF, 0x1B2030),
            sponsors: .hex(0x9B4E71, 0xE9AFC8), treeView: accent,
            system: .hex(0x646873, 0xB0B4BD), userApp: accent,
            developerTool: .hex(0x8A6230, 0xD9B889), other: .hex(0x646873, 0xB0B4BD)
        )
    }
}
