<p align="left"><img src="assets/brand/portpilot-wordmark.svg" width="480" alt="P/ PortPilot"></p>

# P/ PortPilot

PortPilot inspects what is running on the machine: listening TCP/UDP ports, Unix-socket daemons, established connections, and cronjobs. It ships as a macOS menu bar app (`PortPilot.app`), a CLI (`portpilot`), and a terminal UI (`portpilot-tui`), with selected Linux/WSL paths and planned/partial native Windows support. It classifies processes by executable path, kills or pauses processes by port, guards ports against squatters, tracks port lifecycle events on a timeline, and runs a local TCP proxy.

Related docs: [ARCHITECTURE.md](ARCHITECTURE.md) (source tree, tech stack),
[CHANGELOG.md](CHANGELOG.md) (release history), and the wiki-ready
[Security measures](docs/wiki/Security-Measures.md) page.

## Seven interfaces. One local utility.

Choose an interface in **Settings → Appearance → Interface**, or from the
workspace/menu-bar interface picker. It changes the native layout, palette,
typography, and matching popover. The old palette choices have been retired;
saved selections migrate without resetting other preferences.

| Direction | Workspace |
| --- | --- |
| 01 Instrument | Quiet sidebar, listener rows, and process inspector |
| 02 Relay | Dense console, horizontal navigation, selected-process tray |
| 03 Fieldwork | Services grouped by observed repository or working directory |
| 04 Focus | Narrow navigation rail, master list, full process inspector |
| 05 Shell | Monospaced workspace, manual-page header, navigation prompt |
| 06 Play | Rounded service tiles and an inspector |
| 07 Orbit | Spatial listener selection map with an equivalent list view |

Relay, Shell, and Orbit use dark appearance. The other directions follow the
appearance preference. Fonts can be customized after choosing a direction.
Orbit shows up to nine nodes; List shows every matching listener and is also
used when the map has insufficient space. Small workspaces open the inspector
from the selected-process tray. Project groups reflect observed metadata, not
an inferred trust relationship. Bind scope is not invented when unavailable.

Shell accepts `help`, `ports` / `ls`, `find <text>`, `inspect <port>`, `refresh`,
`observations`, `schedules`, and `clear`. It is a navigation prompt, not a system
shell. Process signals, proxies, and cron execution stay in their existing
deliberate controls. An ambiguous port requires selecting the exact process.

**P/** is the wordmark; the plug is the app and menu-bar mark. Vector sources
live in [assets/brand](assets/brand), with a reproducible local icon generator:
`swift scripts/generate_brand.swift`. The
[interactive design studies](docs/design/2026-10-ui-directions/index.html)
remain synthetic references; they do not monitor or control the OS.

## Direct controls and packet summaries

Select a listener in the menu-bar popup or main window for **Pause/Resume** and
**Stop…**. These act on the owning process, including its other ports.
Pause keeps sockets occupied. Stop requires an inline confirmation and the
existing fresh process-identity checks. The app refuses its own process and
missing identities in these quick controls.

The waveform button opens **Packet inspection** for a TCP/UDP port. Choose an
interface and explicitly start a capture: at most 10 seconds / 200 packets,
with a 128 KiB text buffer. Stop, closing the panel, and application shutdown
request capture cancellation; results distinguish failures and partial output.
Only one capture runs at a time.

This uses macOS's system tcpdump with numeric names, non-promiscuous mode,
96-byte snapshots, and quiet summary output. It displays endpoints and protocol
summaries, not payloads, decrypted HTTPS, a complete byte counter, or PID
attribution. Raw snapshots may include initial payload bytes inside tcpdump;
they are not sent to the app as raw data or saved. Endpoint metadata remains
private session memory. No automatic start, privileged helper, or elevated
runtime is provided. If the current user cannot access capture devices, the
feature reports that limitation. This capability is macOS-app-only.

## Requirements

| Component | Requires |
|-----------|----------|
| macOS app | macOS 13.0+, Xcode 15+, Swift 5.9+, [xcodegen](https://github.com/yonaskolb/XcodeGen) |
| CLI / TUI | Swift 5.9+ (macOS; selected Linux/WSL paths; native Windows planned/partial) |
| npm scripts | Node.js 18+ (optional wrappers around the build commands) |

## Installation

### Homebrew (macOS app only)

```bash
brew install --cask sriinnu/tap/portpilot
```

Installs `PortPilot.app` to `/Applications`. Cask source: [sriinnu/homebrew-tap](https://github.com/sriinnu/homebrew-tap). The cask installs only the app — build the CLI and TUI from source.

### GitHub Releases

Download from the [releases page](https://github.com/sriinnu/portpilot/releases).
Public releases use a verified signed main commit and signed annotated version
tag. The local signed handoff contains:

- PortPilot-macOS-app.zip — Developer ID signed app. From 3.5.8 it is also notarized and stapled; `RELEASE.txt` states the notarization status of each release.
- portpilot-macos-cli.zip and portpilot-macos-tui.zip — Developer ID signed universal macOS binaries.
- SHA256SUMS.txt and RELEASE.txt — archive checksums and the audited tag/commit.

GitHub Actions artifacts are internal validation builds and are not public
release assets. Linux CLI/TUI are tested in CI and can be built from source;
this signed macOS handoff does not publish Linux binaries. Notarization and npm
publishing require separate authorization. CI never publishes to npm: on a
published release, `npm-publish.yml` only *stages* the version (trusted
publishing, provenance, no token), and it goes live after the maintainer runs
`npm stage approve <id>` with 2FA. The fallback local publish runs
`PORTPILOT_NPM_PUBLISH_APPROVED=1 npm publish` from signed main
and refuses unless the matching signed annotated tag points at HEAD.

### Build from source (macOS: app + CLI + TUI)

```bash
git clone https://github.com/sriinnu/portpilot.git
cd portpilot
npm run release
```

Builds all three products and installs `PortPilot.app` to `/Applications`, `portpilot` and `portpilot-tui` to `/usr/local/bin`.

App only, without npm:

```bash
./scripts/dev-install.sh           # xcodegen + xcodebuild Release + install to /Applications
./scripts/dev-install.sh --clean   # same, after wiping .build and DerivedData
```

### Build from source (Linux / WSL: CLI + TUI)

Install Swift via [Swiftly](https://www.swift.org/swiftly/documentation/swiftly/getting-started/) if not present:

```bash
curl -L https://swiftlang.github.io/swiftly/swiftly-install.sh | bash
swiftly install latest
swift --version
```

Build and install:

```bash
npm run setup:linux

# or directly
swift build -c release --product portpilot
swift build -c release --product portpilot-tui
sudo cp .build/release/portpilot .build/release/portpilot-tui /usr/local/bin/
```

### Experimental source path (Windows: CLI, not validated)

Native Windows support has not been validated; do not assume macOS security parity. The experimental path requires [Swift for Windows](https://www.swift.org/install/windows/):

```powershell
swift build -c release --product portpilot
```

The TUI requires a POSIX terminal. On Windows, use WSL or the CLI.

## Development

Run from the repo root.

```bash
swift test                                   # unit tests (parsers, cron math, blocklist, layout)
swift build                                  # debug build of CLI + TUI
swift build -c release --product portpilot
swift build -c release --product portpilot-tui

xcodegen generate                            # regenerate PortPilot.xcodeproj from project.yml
xcodebuild -project PortPilot.xcodeproj -scheme PortPilot \
    -configuration Release -derivedDataPath .build/xcode build
```

The Xcode scheme for the CLI target is `PortPilotCLI`, not `portpilot` — the two scheme names collide on case-insensitive filesystems (see CHANGELOG 3.1.0).

CI (`.github/workflows/build.yml`) runs `swift test` on macOS and Linux and builds unsigned internal validation binaries and the app. It publishes nothing: release assets, npm and the Homebrew cask are published by the operator from signed `main` and a signed tag.

### npm scripts

| Script | Effect |
|--------|--------|
| `npm run build` | Build the macOS app (Release, via xcodegen + xcodebuild) |
| `npm run build:debug` | Debug app build |
| `npm run build:cli` / `build:tui` | `swift build -c release` for each product |
| `npm run build:all` | App + CLI + TUI |
| `npm run build:all:linux` | CLI + TUI |
| `npm run setup:linux` | Build CLI + TUI and install to `/usr/local/bin` (uses sudo) |
| `npm run install:app` / `install:cli` / `install:tui` | Copy built artifacts to `/Applications` / `/usr/local/bin` |
| `npm run release` | `build:all` plus install of app, CLI, and TUI |
| `npm run dev` | Debug app build and open it |
| `npm run uninstall` | Remove `/Applications/PortPilot.app` and the two binaries |
| `npm run clean` | Remove `.build` |

### Repository layout

```
Sources/
├── PortPilot/        # macOS menu bar app (SwiftUI + AppKit)
├── TerminalTUI/      # zero-dependency TUI engine (library)
├── PortPilotTUI/     # terminal UI app built on TerminalTUI
├── PortManagerLib/   # shared port/socket/connection/cronjob discovery, classification, proxy
└── PortKillerCLI/    # CLI (swift-argument-parser)
Tests/PortPilotTests/ # unit tests; no shelling out to lsof/ps, no tty
scripts/              # dev-install.sh, create_release.sh, release_signed_macos.sh, generate_sparkle_key.sh
project.yml           # xcodegen spec for PortPilot.xcodeproj
Package.swift         # SwiftPM manifest (CLI, TUI, TerminalTUI, PortManagerLib)
```

File-level tree and tech stack: [ARCHITECTURE.md](ARCHITECTURE.md).

## CLI reference

```bash
portpilot                                  # list (default subcommand)
portpilot list --start 3000 --end 9999     # port range
portpilot list --proto tcp --json          # protocol filter, JSON output
portpilot kill 5173                        # SIGTERM the process on the port
portpilot kill 5173 --force                # SIGKILL
portpilot kill :8080                       # colon prefix accepted
portpilot kill --timeout 3000 5173         # graceful-kill timeout in ms
portpilot pause 5173                       # SIGSTOP — socket stays bound, state kept
portpilot resume 5173                      # SIGCONT — resumes where it froze
portpilot pid 8080                         # print PID for a port
portpilot pids 3000 3001 3002              # PIDs for multiple ports
portpilot find --start 8000 --end 8999     # free ports in a range
portpilot kill-all                         # kill every listed process
portpilot connections                      # established connections, grouped by process
portpilot connections --suspect            # only processes with >50 connections
portpilot connections --blocklist          # only blocklisted remote hosts
portpilot connections --threats            # threat-engine assessment (same as Security Center)
portpilot connections --threats --json     # findings as JSON for scripts/agents
portpilot connections --watch 15           # headless auto-alert every 15s (Ctrl+C to stop)
portpilot connections --kill 12345         # kill by PID
portpilot connections --json
portpilot blocklist list                   # list blocklisted hosts
portpilot blocklist add 203.0.113.9        # flag an IP, domain, .suffix, or IPv4 CIDR
portpilot blocklist remove 203.0.113.9     # un-blocklist
portpilot cronjobs                         # user + system crontab entries
portpilot cronjobs --user-only             # personal crontab only
portpilot cronjobs --system-only           # /etc/crontab and /etc/cron.d only
portpilot cronjobs --json
portpilot docker                           # Docker containers behind ports
portpilot program-pids --program node      # PIDs for a program name
portpilot program-kill --program node      # kill all PIDs for a program name
portpilot proxy --port 1080 --ssh user@host  # runs ssh -D 1080 -N user@host (SOCKS)
portpilot tui                              # launch portpilot-tui
portpilot interactive                      # basic interactive kill mode
```

`--json` output fields for `list`: `port`, `protocolName`, `pid`, `user`, `command`, `fullCommand`, `parentPID`, `startTime`, `workingDirectory`, `processPath`, `socketPath`, `cpuUsage`, `memoryMB`.

## TUI

```bash
portpilot-tui        # or: portpilot tui
```

Tabs: Ports, Sockets, Schedules, Connections. Blocklisted connections are marked in the Connections tab; press `!` there for a threats-only view (same engine as `connections --threats`).

| Key | Action |
|-----|--------|
| `↑↓` / `j` `k` | Navigate |
| `Enter` | Kill process (confirmation prompt) |
| `/` | Search / clear filter |
| `!` | Threats-only filter (Connections tab) |
| `Tab` | Switch tab |
| `i` | Process detail view (info + connections) |
| `r` | Refresh |
| `q` | Quit |

## Configuration

`~/.portpilot/blocklist.txt` — one entry per line: domain (with or without a leading `.`, matching the base name and subdomains), exact IPv4/IPv6 address, or IPv4 CIDR range. IPv6 CIDRs are not supported by this matcher. This list flags connections for detection; it does not block traffic. See the app's **Settings → Security FAQ**, [Security measures](docs/wiki/Security-Measures.md), or [mission.md](mission.md) for precautions.

```
upload.dev
52.45.119.88
192.168.1.0/24
2001:db8::1
.evil.com
```

Matching connections are flagged in `portpilot connections`, the TUI, and the menu bar app.

## Platform support

| Platform | App | Port discovery | Connections |
|----------|-----|----------------|-------------|
| macOS 13+ | Menu bar + window | `lsof` + `proc_pidpath` | `lsof` |
| Linux / WSL | - | `ss -tulnp` | `ss` |
| Windows (planned/partial, unvalidated) | - | `netstat -ano` + `tasklist /FO CSV` source path | `netstat` source path |

## Using TerminalTUI as a library

`TerminalTUI` is exported as a standalone SwiftPM library (no dependencies):

```swift
dependencies: [
    .package(url: "https://github.com/sriinnu/portpilot.git", from: "3.0.0"),
],
targets: [
    .executableTarget(
        name: "MyApp",
        dependencies: [.product(name: "TerminalTUI", package: "portpilot")]
    ),
]
```

```swift
import TerminalTUI

struct MyScreen: TUIScreen {
    mutating func render(into screen: inout Screen) {
        screen.put(row: 0, col: 0, text: "Hello", style: ANSI.bold + ANSI.fg(.cyan))
    }
    mutating func handleKey(_ key: KeyEvent) -> ScreenAction {
        switch key {
        case .char("q"): return .quit
        default: return .`continue`
        }
    }
}

let app = TUIApp(screen: MyScreen())
app.run()
```

## License

MIT — see [LICENSE](LICENSE).
