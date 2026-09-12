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
    /// Layered paper strata for hero surfaces (dropdown, traffic band,
    /// preview card) — the diorama gradient, top to bottom. nil on every
    /// theme whose character is flat color.
    var strataTop: ThemeColorPair? = nil
    var strataMiddle: ThemeColorPair? = nil
    var strataBottom: ThemeColorPair? = nil
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

    /// The strata as a top-to-bottom gradient, or nil when this theme is
    /// flat. With a middle stop present the gradient reads as three paper
    /// layers; without it, two.
    var strataGradient: LinearGradient? {
        guard let top = strataTop, let bottom = strataBottom else { return nil }
        if let middle = strataMiddle {
            return LinearGradient(
                colors: [top.color, middle.color, bottom.color],
                startPoint: .top, endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [top.color, bottom.color],
            startPoint: .top, endPoint: .bottom
        )
    }
}
