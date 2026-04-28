import SwiftUI
import AppKit

struct ThemePalette {
    let cloudflare: ThemeColorPair
    let kubernetes: ThemeColorPair
    let local: ThemeColorPair
    let database: ThemeColorPair
    let ssh: ThemeColorPair
    let orbstack: ThemeColorPair
    let proxy: ThemeColorPair
    let connected: ThemeColorPair
    let connectedBackground: ThemeColorPair
    let error: ThemeColorPair
    let warning: ThemeColorPair
    let accent: ThemeColorPair
    let sponsors: ThemeColorPair
    let treeView: ThemeColorPair
    let system: ThemeColorPair
    let userApp: ThemeColorPair
    let developerTool: ThemeColorPair
    let other: ThemeColorPair

    /// I expose the currently selected palette from persisted app settings.
    static var current: ThemePalette {
        switch AppSettings.shared.visualTheme {
        case .classic:    return .classic
        case .graphite:   return .graphite
        case .sunset:     return .sunset
        case .oceanic:    return .oceanic
        case .noir:       return .noir
        case .retro:      return .retro
        case .terminal:   return .terminal
        case .paperwhite: return .paperwhite
        case .synthwave:  return .synthwave
        case .solarized:  return .solarized
        }
    }
}
