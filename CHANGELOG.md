# Changelog

All notable changes to PortPilot will be documented in this file.

## [Unreleased]

### Added
- **Liquid Display UI** — glass-panel menu bar dropdown with header branding, live stats, integrated search, filter chips, Top Activity section, and sponsor footer
- **List/Tree View toggle** — switch between connection-type grouping (Local/Database/Kubernetes/Cloudflare/SSH) and process-name grouping within the dropdown
- **Schedules section** — cronjobs displayed in the dropdown with schedule, command, source badge, and next-run time
- **LiquidCard settings** — all Settings panes converted to themed glass card components
- **Retro theme** — warm and nostalgic color scheme with American Typewriter + Courier New font pairing
- **Add Program button** — custom programs can now be created from Settings
- **Build & notarize scripts** — `build-and-notarize.sh`, `notarize.sh`, `setup-notarization.sh`
- **More menu** — dropdown menu with Refresh, Kill All (with confirmation), Settings, Quit and click-outside dismiss
- **Connection type sections** — ports grouped by Local, Database, Kubernetes, Cloudflare, SSH with colored icons

### Changed
- **Theme sync** — dropdown, settings, and main window all derive colors from the same theme palette
- **Theme.Alert** colors now derive from palette (`connected`, `warning`, `error`) instead of hardcoded values
- **Theme.Liquid** uses computed properties from `Theme.Surface` and `Theme.palette` for full theme consistency
- **MenuBarController** marked `@MainActor` for Swift 6 concurrency safety
- **Event monitor** scoped to panel open/close lifecycle instead of always-on
- **Panel positioning** uses button's screen instead of `NSScreen.main` for multi-monitor support
- **README** updated with Liquid Display features and Retro theme

### Fixed
- **Menu bar icon invisible** — image properties (size, isTemplate) were mutated on a copy instead of the original
- **Port numbers with commas** — `Text(verbatim:)` used for all integer display to prevent locale formatting
- **Panel memory leak** — panel niled out on dismiss to free SwiftUI hierarchy
- **Tree View button** closing the panel — now toggles view mode within the dropdown
- **NotificationManager** delegate callback dispatched to main thread for `@Published` safety
- **Strong self captures** in Tasks and closures replaced with `[weak self]`
- **Retain cycle** in MenuBarPanel `close()` animation fixed with `[weak self]`

## [3.0.0] - 2025-03-15

### Added
- Cross-platform Terminal UI (TerminalTUI engine)
- TUI with Ports, Sockets, Connections, Schedules tabs
- Process detail view with connection list
- Cronjob discovery and display
- Connection monitoring with blocklist detection

## [2.0.0] - 2024-12-01

### Added
- macOS menu bar app with SwiftUI
- Port discovery, kill, proxy
- 5 color themes (Classic, Graphite, Sunset, Oceanic, Noir)
- Custom font support
- CLI tool (cross-platform)
