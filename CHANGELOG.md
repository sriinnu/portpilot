# Changelog

All notable changes to PortPilot will be documented in this file.

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
- **Nord theme** — cool-toned palette joining the existing theme set
- **Pause/Resume for processes** — SIGSTOP/SIGCONT from port rows and the dropdown; a frozen process keeps its port and full state
- **dev-install script** — `scripts/dev-install.sh` builds Release and installs to `/Applications`; `--clean` wipes build state first

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
- **End-to-end review sweep (correctness, threading, a11y)** — cronjob stop matching pinned to exec+args prefix instead of basename; docker façade errors surfaced instead of swallowed; port-watcher callbacks and cron stop moved off the main thread; consume-once error ownership in the model; PID-direct kills from every surface so a late binder can't be killed by mistake

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
