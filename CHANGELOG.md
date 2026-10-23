# Changelog

All notable changes to PortPilot will be documented in this file.

## [Unreleased]

## [3.5.7] - 2026-10-23

- Add Support heart and sriinnu GitHub links to the menu-bar and main-window footers.
- Prepare the cumulative security, seven-interface, process-control and bounded packet-summary changes for signed release.


## [3.5.6] - 2026-10-23

- Show the selected process, protocol and endpoint directly on Pause/Resume and Stop buttons, with its PID below and complete target details in tooltips.
- Keep the confirmation bound to the selected process snapshot; refresh pause state only for the same observed process incarnation.
- Prepare local test build 3.05.0006.


## [3.5.5] - 2026-10-23

- Add direct process Pause/Resume and confirmed Stop controls to the menu-bar popup and selected listener workspace.
- Anchor the popup to the menu-bar icon with an integrated pointer.
- Add opt-in, bounded macOS packet-summary inspection with cancellation, permission reporting, and no payload display or capture-file storage.
- Prepare local test build 3.05.0005.


## [3.5.4] - 2026-10-23

- Match native typography to the design studies: Georgia Fieldwork headings, SF Mono code and terminal directions, and system sans body text.
- Correct the P/ wordmark and improve readability of workspace and menu-bar metadata.
- Prepare the typography local test build as `3.05.0004`.

## [3.5.3] - 2026-10-23

- Replace retired palettes with seven native workspace and menu-bar directions: Instrument, Relay, Fieldwork, Focus, Shell, Play, and Orbit.
- Adopt the P/ wordmark and plug mark across the app, menu bar, CLI/TUI headers, and README.
- Prepare the seven-interface local test build as `3.05.0003`.

## [3.5.2] - 2026-10-23

- Prepare the reviewed security and monitoring UI changes for local installed testing as `3.05.0002`.

## [3.5.1] - 2026-10-22

### Security
- Harden process-incarnation binding, Guard cancellation/baselines, cron transactions and alert-list persistence; add source-backed security guidance and an in-app FAQ.
- Require signed release artifacts, commits and annotated tags; replace automatic release/publish/install paths with fail-closed local verification. Display test builds as `3.05.0001`.
- See `docs/SECURITY_REVIEW_2026-10-22.md` for findings, safe regression paths and remaining limits.

## [3.5.0] - 2026-10-02

### Added
- **Threat engine v1** — behavioral bot/attack detection over established connections: blocklisted contact (critical), high connection count (warning, legacy >50 preserved), remote fan-out / scan shape (warning), new-remote burst / beaconing shape (warning), first-seen dialer (info). Learning baseline seeds silently on first snapshot; details in `docs/THREAT_ENGINE.md`.
- **Background auto-alert** — `ThreatMonitorStore` polls every 15s, pages once per novel signal (15-min cooldown, coalesced summary notification), and writes every finding to the activity log. Critical findings turn the menubar red.
- **Security Center** — sidebar Security tab: status header with last-check proof, severity filter chips, finding cards with Kill / Freeze (SIGSTOP) / Copy remote / Block host actions, detection tuning steppers, and persisted history (`~/.portpilot/threat-history.json`).
- **CLI**: `portpilot connections --threats [--json]`, `portpilot connections --watch <seconds>` (headless auto-alert, baseline seeds on tick one), `portpilot blocklist list|add|remove`.
- **TUI**: `!` toggles threats-only in the Connections tab (composes with `/` search).
- **Sentinel theme** — SOC watch-floor aesthetic, phosphor-on-slate, dark-native. Severity colors (`Theme.Severity`) are fixed semantic tokens so urgency survives every theme.
- **Skins, not swatches** — culled Papercraft, Nord, Retro, Terminal, Synthwave (five same-silhouette recolors). Selecting a skin now applies its full skin at once: palette + fonts (auto, missing families skipped) + geometry; Noir takes the tight square-corner geometry. Skin contract: `docs/THEMES.md`.
- **Folio skin** — first complete skin under the contract: editorial print voice (Georgia UI + SF Mono, both macOS-shipped), ink blacks, print-paper light mode, night-desk dark mode, one oxblood-red accent. Tapping it re-voices the whole app.

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
