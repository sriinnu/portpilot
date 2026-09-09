# PortPilot

PortPilot inspects what is running on the machine: listening TCP/UDP ports, Unix-socket daemons, established connections, and cronjobs. It ships as a macOS menu bar app (`PortPilot.app`), a cross-platform CLI (`portpilot`), and a terminal UI (`portpilot-tui`). It classifies processes by executable path, kills processes by port, and runs a local TCP proxy.

Related docs: [ARCHITECTURE.md](ARCHITECTURE.md) (source tree, tech stack), [CHANGELOG.md](CHANGELOG.md) (release history).

## Requirements

| Component | Requires |
|-----------|----------|
| macOS app | macOS 13.0+, Xcode 15+, Swift 5.9+, [xcodegen](https://github.com/yonaskolb/XcodeGen) |
| CLI / TUI | Swift 5.9+ (macOS, Linux, WSL, Windows) |
| npm scripts | Node.js 18+ (optional wrappers around the build commands) |

## Installation

### Homebrew (macOS app only)

```bash
brew install --cask sriinnu/tap/portpilot
```

Installs `PortPilot.app` to `/Applications`. Cask source: [sriinnu/homebrew-tap](https://github.com/sriinnu/homebrew-tap). The cask installs only the app — build the CLI and TUI from source.

### GitHub Releases

Download from the [releases page](https://github.com/sriinnu/portpilot/releases). Tag builds attach:

- `PortPilot-macOS-app-unsigned.zip` — ad-hoc signed, not notarized. On first launch, right-click the app and choose Open. A signed and notarized `PortPilot-macOS-app.zip` is attached when published from the maintainer's local release flow.
- `portpilot-macos-cli`, `portpilot-macos-tui` — universal binaries (arm64 + x86_64)
- `portpilot-linux-cli`, `portpilot-linux-tui`
- `SHA256SUMS.txt`

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

### Build from source (Windows: CLI)

Requires [Swift for Windows](https://www.swift.org/install/windows/):

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

CI (`.github/workflows/build.yml`) runs `swift test` on macOS and Linux, builds the universal binaries and the app, and publishes the release artifacts listed above on `v*` tags.

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
portpilot pid 8080                         # print PID for a port
portpilot pids 3000 3001 3002              # PIDs for multiple ports
portpilot find --start 8000 --end 8999     # free ports in a range
portpilot kill-all                         # kill every listed process
portpilot connections                      # established connections, grouped by process
portpilot connections --suspect            # only processes with >50 connections
portpilot connections --blocklist          # only blocklisted remote hosts
portpilot connections --kill 12345         # kill by PID
portpilot connections --json
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

Tabs: Ports, Sockets, Schedules, Connections. Blocklisted connections are marked in the Connections tab.

| Key | Action |
|-----|--------|
| `↑↓` / `j` `k` | Navigate |
| `Enter` | Kill process (confirmation prompt) |
| `/` | Search / clear filter |
| `Tab` | Switch tab |
| `i` | Process detail view (info + connections) |
| `r` | Refresh |
| `q` | Quit |

## Configuration

`~/.portpilot/blocklist.txt` — one entry per line: domain, domain suffix (leading `.` matches subdomains), IP, IPv6 prefix, or CIDR range.

```
upload.dev
52.45.119.88
192.168.1.0/24
2a06:98c1:310b
.evil.com
```

Matching connections are flagged in `portpilot connections`, the TUI, and the menu bar app.

## Platform support

| Platform | App | Port discovery | Connections |
|----------|-----|----------------|-------------|
| macOS 13+ | Menu bar + window | `lsof` + `proc_pidpath` | `lsof` |
| Linux / WSL | - | `ss -tulnp` | `ss` |
| Windows | - | `netstat -ano` + `tasklist /FO CSV` | `netstat` |

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
