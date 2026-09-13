# Changelog

All notable changes to PortPilot will be documented in this file.

## [Unreleased]

## [3.4.0] - 2026-09-13

### Added
- **Papercraft theme** — layered paper dioramas. Light mode is the sunset sky (coral → amber → cream strata), dark mode the ocean scene (deep indigo → teal → dusk teal). Coral accent with cream accent text; forest-teal connected, plum ssh, sienna database, peach cloudflare. Font pairing: Georgia + Menlo.
- **Layered-paper strata in the theme system** — palettes can declare three optional strata stops (`strataTop/Middle/Bottom`), rendered as stacked sheets rather than a gradient: each color holds a flat band, and bands meet at a seam built like cut paper — the upper sheet's cast shadow over the lower sheet's lit lip. Laid muted and translucent over the menu bar dropdown and the settings theme previews (each card shows its own theme's strata); flat themes keep the existing solid fills everywhere.

## [3.3.0] - 2026-09-09

### Added
- **Port guard** — arm a guard on a port from Settings → Guard. Holders present at arm time are grandfathered; anything new that binds the port is evicted within ~2 seconds (SIGTERM first, SIGKILL if it lingers), with a notification and an activity-log entry per eviction. Guards stay armed regardless of the background-monitoring toggle, and a port cannot be both guarded and reserved — the two refuse each other in both directions.
- **Timeline tab** — port lifecycle as a first-class stream in the inspector: bound, released, killed, paused, resumed, and guard events, newest first, rendered from the structured event field rather than message parsing, with a "This port" filter. Port changing hands reads as one release plus one bind.
- **Menubar glanceability** — the menu bar icon carries a count of port changes since the dropdown was last opened (cleared by the next glance), switches to a paused glyph while any known process is SIGSTOPped, and turns critical on connection alerts.
- **Project grouping** — the dropdown's Tree View gains a Process/Project axis: groups by git repo (falling back to the working directory), so the ports one project owns read as one group with an honest label.
- **Narrative overview** — the inspector's Overview pane opens with the process story — uptime and start time, repo/branch, framework, parent process, tunnel target, frozen state — assembled from enrichment the refresh already resolved. Missing facts are omitted, not guessed.

### Changed
- I split the `PortViewModel` god object into domain stores — `ActivityLogStore`, `CronjobController`, `PortGuardStore`, and `TunnelInspector` — with the view model relaying their change notifications so views keep observing one object. No behavior change; ~250 lines lighter and each domain is now testable in isolation.

## [3.2.0] - 2026-09-09

### Added
- I added a Pause/Resume toggle for cronjobs in the Schedules tab. Personal crontab entries can be paused (commented out with a recoverable `#PORTPILOT_PAUSED#` marker) and resumed without losing the original schedule or command; system cronjobs stay read-only.
- I added a Run Now button to trigger a cronjob's command immediately, and a Stop button to kill an in-flight run — tracked live with a spinner on the row.
- I added run history per cronjob: last run time, duration, exit code, and run count, persisted across restarts and shown in the cronjob detail panel and Activity log.

### Fixed
- I fixed a crontab parser bug where multi-word personal crontab commands (e.g. `/bin/echo hello`) were misparsed as `user=/bin/echo command=hello`. The parser assumed the user-column format used by `/etc/crontab` and `/etc/cron.d` even for personal `crontab -l` output, which never has a user column.
- I fixed a scheme name collision in the Xcode project: `PortPilot` and `portpilot` schemes wrote to the same filename on case-insensitive filesystems, so regenerating the project with `xcodegen` could silently repoint the shared build scheme at the wrong target. Renamed the CLI scheme to `PortPilotCLI`.
- I fixed `crontab` writes silently failing on long temp file paths — macOS's `crontab` binary truncates file path arguments past ~100 bytes, and `FileManager.temporaryDirectory` resolves to a long per-app path. Cronjob pause/resume now writes to a short `/tmp` path instead.

### Chore
- I cleaned up stale Xcode DerivedData build products so Spotlight only shows one PortPilot.app instead of three.

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
