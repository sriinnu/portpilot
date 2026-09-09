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
    /// Text color placed ON TOP of the accent (chip labels, badge text).
    /// nil means white — the right default everywhere except Noir's dark
    /// mode, whose near-white accent makes white text invisible.
    var onAccent: ThemeColorPair? = nil
    let sponsors: ThemeColorPair
    let treeView: ThemeColorPair
    let system: ThemeColorPair
    let userApp: ThemeColorPair
    let developerTool: ThemeColorPair
    let other: ThemeColorPair

    /// I expose the currently selected palette from persisted app settings.
    static var current: ThemePalette {
        AppSettings.shared.visualTheme.palette
    }
}
