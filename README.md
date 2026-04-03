# PortPilot

<p align="center">
  <img src="assets/portpilot.svg" alt="PortPilot" width="128" height="128">
</p>

<h3 align="center">Port management from your menu bar — and your terminal</h3>

<p align="center">
  Monitor ports, discover local app daemons, proxy traffic, and kill processes — from the macOS menu bar <strong>or</strong> a rich terminal UI on any platform. With first-class support for SSH, Kubernetes, and Cloudflare tunnels.
</p>

<p align="center">
  <a href="https://www.npmjs.com/package/@sriinnu/portpilot"><img src="https://img.shields.io/npm/v/@sriinnu/portpilot?style=flat-square&logo=npm&logoColor=white&color=cb3837" alt="npm"></a>
  <img src="https://img.shields.io/badge/macOS-13.0%2B-brightgreen?style=flat-square" alt="macOS 13.0+">
  <img src="https://img.shields.io/badge/Linux-CLI-orange?style=flat-square" alt="Linux CLI">
  <img src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" alt="MIT License">
</p>

---

## Why PortPilot?

Port conflicts kill developer flow. PortPilot gives you instant visibility into every listening port **and** every local app daemon on your machine.

Unlike basic `lsof` wrappers, PortPilot:
- **Classifies processes** as System, App, or Developer Tool — so you see what matters
- **Detects tunnels** — SSH forwards, `kubectl port-forward`, Cloudflare tunnels with meaningful names
- **Discovers Unix sockets** — local daemons like databases, dev servers, custom services
- **Proxies traffic** — native TCP proxy built on Apple's Network.framework
- **Lives in your menu bar** — no Dock icon, zero distraction

## Features

### Menu Bar App
- **Ports tab** — live port list grouped by connection type (Local, Database, SSH, K8s, Cloudflare)
- **Sockets tab** — Unix socket processes with PID, classification badge, and socket path
- **Connections tab** — all established outbound connections grouped by process, with blocklist detection
- **Schedules tab** — cronjobs (user crontab + system cron) with next-run times
- **CPU usage** — real-time per-process CPU % with color-coded badges (green/yellow/orange/red)
- **Filter pills** — TCP / UDP / Unix protocol filters, connection type icons with counts, hide system toggle
- **Process classification** — each process labeled as System, App, or Developer using `proc_pidpath`
- **Tunnel detection** — SSH, Kubernetes, Cloudflare with smart name extraction
- **Blocklist detection** — 🚨 markers for connections to blocklisted hosts (matches `~/.portpilot/blocklist.txt`)
- **Inline actions** — kill, copy, stop tunnel — right from the dropdown
- **No Dock icon** — pure menu bar accessory app

### Main Window
Open via menu bar → "Open PortPilot"

- **Port list** with filter pills (TCP/UDP/Unix, Web/Database/Dev/System/Favorites)
- **CPU usage** — inline CPU % badge per process, color-coded by load
- **Configuration panel** — connection details, process class, PID, uptime, CPU, CWD, port mapping
- **Quick Proxy** — start/stop TCP proxy for any port from the config panel
- **Port flow visualization** — ASCII diagram showing traffic path
- **Logs panel** — activity log with per-port filtering
- **Favorites, history, custom programs, reserved ports**

### Appearance & Fonts
Fully customizable look and feel from Settings → Appearance:

- **5 color themes** — Classic, Graphite, Sunset, Oceanic, Noir — each with a recommended font pairing
- **Custom fonts** — pick any system font for UI and monospaced text, or drop `.ttf`/`.otf` files into the `Fonts/` folder
- **Font size** — adjustable from 9px to 18px, applied consistently across all views
- **Custom fonts folder** — `Fonts/` in the project root (next to `Sources/`), or `~/Library/Application Support/PortPilot/Fonts/`

| Theme | Character | Recommended Fonts |
|-------|-----------|-------------------|
| Classic | Vibrant and balanced | System Default + System Monospaced |
| Graphite | Calm and professional | SF Pro + SF Mono |
| Sunset | Warm and expressive | Avenir Next + Menlo |
| Oceanic | Deep and focused | SF Pro Rounded + SF Mono |
| Noir | Sharp and minimal | Helvetica Neue + Fira Code |

### Native TCP Proxy
Built on Apple's Network.framework (NWListener + NWConnection):
- Forward traffic between any local ports
- Bidirectional relay with byte counting
- Start/stop from the Configuration panel
- Active proxy indicator with "Stop All"

### Process Classification
Uses `proc_pidpath` to resolve executable paths and classify by heuristic:

| Type | Examples | How detected |
|------|----------|-------------|
| **System** | mDNSResponder, WindowServer, launchd | `/System/`, `/usr/libexec/`, known daemons |
| **Developer** | node, postgres, docker, nginx, redis | Homebrew paths, known dev tools |
| **App** | Electron apps, .app bundles | `/Applications/`, `.app/` in path |
| **Other** | Unclassified | Fallback |

### Blocklist Detection
Suspicious connections are flagged by matching against `~/.portpilot/blocklist.txt`:

```
# ~/.portpilot/blocklist.txt — one domain, IP, or CIDR per line
upload.dev
52.45.119.88
192.168.1.0/24
2a06:98c1:310b
```

Supports:
- Exact domain/IP matching
- Domain suffix matching (`.evil.com` matches `cdn.evil.com`)
- IPv6 prefix matching
- CIDR ranges
- Blocklisted connections show 🚨 in CLI, TUI, and menu bar

### Terminal UI (Cross-Platform)
A full-featured terminal interface — works on macOS, Linux, and WSL. Zero dependencies.

```bash
portpilot-tui
```

```
╭─────────────────────────────────────────────────────────────────────────╮
│                        PortPilot TUI                            Linux  │
│  Ports   Sockets   Connections   Schedules                             │
│─────────────────────────────────────────────────────────────────────────│
│  PORT    PROTO  PID      CPU%     MEM     USER         COMMAND    TYPE │
│  ─────────────────────────────────────────────────────────────────────  │
│  3000    TCP    12345    0.3      45M     user         node       Web  │
│▸ 5432    TCP    789      1.2      120M    postgres     postgres   DB   │
│  8080    TCP    4567     5.1      300M    user         java       Web  │
│  6379    TCP    1122     0.1      8M      redis        redis      DB   │
│  9090    TCP    3344     0.0      15M     user         grafana    Web  │
│                                                                    ░░  │
│                                                                    ░░  │
├─────────────────────────────────────────────────────────────────────────┤
│ ↑↓/jk Navigate │ Enter Kill │ / Search │ Tab Switch │ i Info │ q Quit │
│ 5 process(es) on Linux                                                 │
╰─────────────────────────────────────────────────────────────────────────╯
```

**Keybindings:**

| Key | Action |
|-----|--------|
| `↑↓` / `j` `k` | Navigate |
| `Enter` | Kill process (with confirmation) |
| `/` | Search / clear filter |
| `Tab` | Switch between Ports, Sockets, Connections, Schedules tabs |
| `i` | View detailed process info + connections |
| `r` | Refresh |
| `q` | Quit |

**Connections tab** shows all established outbound connections grouped by process with blocklist 🚨 markers.

**Schedules tab** shows cronjobs (user + system) with next-run calculation.

**Detail View** — press `i` on any port:
```
╭ Process Info ──────────────────────────────────────────╮
│  Port:        5432                                     │
│  Protocol:    TCP                                      │
│  PID:         789                                      │
│  User:        postgres                                 │
│  Command:     postgres                                 │
│  CPU:         1.2%                                     │
│  Memory:      120M                                     │
│  Path:        /usr/lib/postgresql/15/bin/postgres       │
│  Work Dir:    /var/lib/postgresql/15/main               │
╰────────────────────────────────────────────────────────╯
╭ Connections (3) ───────────────────────────────────────╮
│  LOCAL ADDRESS        REMOTE ADDRESS        STATE      │
│  127.0.0.1:5432      127.0.0.1:48210       ESTABLISHED│
│  127.0.0.1:5432      127.0.0.1:48212       ESTABLISHED│
│  *:5432              *:*                    LISTEN     │
╰────────────────────────────────────────────────────────╯
 Esc Back │ x Kill │ X Force Kill │ q Quit
```

### CLI Tool (Cross-Platform)
```bash
portpilot list                          # All listening ports (with CPU%)
portpilot list --start 3000 --end 9999  # Port range
portpilot list --proto tcp --json       # JSON output (includes cpuUsage)
portpilot kill 5173 --force             # Kill by port
portpilot kill :8080                    # Colon prefix syntax
portpilot pid 8080                      # Get PID for port
portpilot pids 3000 3001 3002           # Multiple PIDs
portpilot connections                   # All established connections (grouped by process)
portpilot connections --suspect         # Only processes with >50 connections
portpilot connections --kill 12345      # Kill process by PID
portpilot connections --json            # JSON output
portpilot schedules                     # User + system cronjobs
portpilot schedules --json              # JSON output
portpilot interactive                   # TUI mode
portpilot proxy --port 1080 --host user@server  # SOCKS proxy
```

CLI table output includes CPU%, memory, and project/source info:
```
PORT     PROTO  PID      CPU%     MEM      USER         COMMAND            PATH/PROJECT
3000     TCP    21082    0.0      45M      user         node               wooosh/client
5432     TCP    63341    9.4      120M     user         postgres           postgresql/15/main
8080     TCP    4567     5.1      300M     user         java               my-api/server
```

**Connections output** with blocklist detection:
```
REMOTE              PROCESS      PID     USER     STATE         COUNT
52.45.119.88:443    node         12345   user     ESTABLISHED   1847   🚨
54.210.12.45:443    chrome       999     user     ESTABLISHED   23
...
```

**Schedules output:**
```
SCHEDULE          NEXT RUN        USER     COMMAND                        SOURCE
@hourly          04-03 14:00     user     /usr/bin/some-script.sh       user
*/5 * * * *      04-03 13:35     root     /usr/bin/monitoring.sh        /etc/cron.d/sys
```

## Installation

### Download from GitHub Releases
For end users, the easiest path is the Releases page:

- Download `PortPilot-macOS-app.zip`
- Unzip it
- Move `PortPilot.app` to `/Applications`

The release currently attaches:

- `PortPilot-macOS-app.zip`
- `portpilot-macos-cli`
- `SHA256SUMS.txt`

### macOS (App + CLI + TUI)
```bash
git clone https://github.com/sriinnu/portpilot.git
cd portpilot
npm run release
```

This builds everything and installs:
- `PortPilot.app` → `/Applications/` (menu bar app)
- `portpilot` CLI → `/usr/local/bin/`
- `portpilot-tui` → `/usr/local/bin/` (terminal UI)

```bash
portpilot list              # CLI: list all listening ports
portpilot-tui               # TUI: full interactive terminal UI
```

### Linux / WSL

**1. Install Swift** (if not already installed):
```bash
curl -L https://swiftlang.github.io/swiftly/swiftly-install.sh | bash
source ~/.profile  # or restart your shell
swiftly install latest
swift --version    # verify: should show Swift 6.x
```
> See the official [Swiftly Getting Started guide](https://www.swift.org/swiftly/documentation/swiftly/getting-started/) for details.

**2. Build & install:**
```bash
git clone https://github.com/sriinnu/portpilot.git
cd portpilot
npm run setup:linux   # builds CLI + TUI and installs to /usr/local/bin
```

Or step by step:
```bash
npm run build:all:linux
sudo cp .build/release/portpilot /usr/local/bin/
sudo cp .build/release/portpilot-tui /usr/local/bin/
```

**3. Use it:**
```bash
portpilot list              # all listening ports with project paths
portpilot tui               # launch rich terminal UI
portpilot-tui               # direct launch
portpilot kill 8080         # kill by port
```

### Windows
Requires [Swift for Windows](https://www.swift.org/install/windows/):
```powershell
git clone https://github.com/sriinnu/portpilot.git
cd portpilot
swift build -c release --product portpilot
copy .build\release\portpilot.exe "C:\Program Files\PortPilot\"
```

Uses `netstat` + `tasklist` automatically:
```powershell
portpilot list              # all listening ports
portpilot kill 5000 --force # force kill
portpilot list --json       # pipe to tools
```

> **Note:** The TUI (`portpilot-tui`) requires a POSIX terminal and works on macOS, Linux, and WSL. On Windows, use WSL or the CLI directly.

> **No config, no setup, no runtime dependencies.** Platform detection is automatic — same interface everywhere.

### npm scripts
```bash
# macOS
npm run build            # Build macOS app (xcodebuild)
npm run release          # Build all + install app/CLI/TUI

# Linux / WSL
npm run setup:linux      # One-command: build + install CLI + TUI
npm run build:all:linux  # Build CLI + TUI only

# Common
npm run build:cli        # Build CLI
npm run build:tui        # Build TUI
npm run install:cli      # Install CLI to /usr/local/bin
npm run install:tui      # Install TUI to /usr/local/bin
npm run uninstall        # Remove everything
npm run clean            # Remove build artifacts
```

## Platform Support

| Platform | GUI App | TUI | CLI | Port Discovery | Install |
|----------|---------|-----|-----|---------------|---------|
| macOS 13+ | Menu bar + window | `portpilot-tui` | `portpilot` | `lsof` + `proc_pidpath` | `npm run release` |
| Linux | - | `portpilot-tui` | `portpilot` | `ss` | `npm run build:all:linux` |
| WSL | - | `portpilot-tui` | `portpilot` | `ss` | `npm run build:all:linux` |
| Windows | - | via WSL | `portpilot` | `netstat` + `tasklist` | `swift build -c release` |

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+R` | Refresh ports |
| `Cmd+F` | Search |
| `Cmd+,` | Settings |

## Architecture

```
Sources/
├── PortPilot/                  # macOS menu bar app (SwiftUI + AppKit)
│   ├── PortPilotApp.swift            # Pure AppKit entry (no Dock icon)
│   ├── ContentView.swift             # Main window layout
│   ├── PortViewModel.swift           # State, filtering, tunnel detection
│   ├── MenuBarController.swift       # Status item + panel management
│   ├── MenuBarDropdownView.swift     # Dropdown with Ports/Sockets/Connections/Schedules tabs
│   ├── MenuBarPanel.swift            # Floating NSPanel
│   ├── PortListPanel.swift           # Port list with classification badges
│   ├── ConfigurationPanel.swift      # Config + proxy controls
│   ├── MainWindowToolbar.swift       # Toolbar with filter pills
│   ├── LogsPanel.swift               # Activity logs
│   ├── Theme.swift                   # 5 color themes
│   ├── FontManager.swift             # Custom font loading
│   ├── SettingsView.swift            # Preferences (appearance, fonts, themes)
│   └── AppSettings.swift             # UserDefaults + font/theme settings
├── TerminalTUI/                # Reusable TUI engine (zero dependencies)
│   ├── Terminal.swift                # Raw mode, terminal size, cursor, alt screen
│   ├── ANSI.swift                    # Escape codes — 16/256/TrueColor, styles
│   ├── KeyEvent.swift                # Key reading — arrows, ctrl, UTF-8, escape seqs
│   ├── Screen.swift                  # Double-buffered diff renderer
│   ├── Widget.swift                  # Widget protocol + geometry types
│   ├── Box.swift                     # Bordered container (4 border styles)
│   ├── Table.swift                   # Scrollable table with columns + selection
│   ├── StatusBar.swift               # Bottom bar with keybinding hints
│   └── App.swift                     # TUIApp event loop + screen stack
├── PortPilotTUI/               # Terminal UI app (macOS + Linux + WSL)
│   ├── main.swift                    # Entry point
│   ├── PortListScreen.swift          # Port/Socket/Connection/Schedule tables, search, kill
│   ├── PortDetailScreen.swift        # Process info + connections
│   ├── ConnectionDetailScreen.swift  # Connection remote details, kill option
│   └── CronjobDetailScreen.swift    # Cronjob schedule info, next run
├── PortManagerLib/             # Shared library (all platforms)
│   ├── PortManager.swift             # Port + socket + connection + cronjob discovery
│   ├── ProcessClassifier.swift       # proc_pidpath classification
│   ├── TCPProxyManager.swift         # Network.framework TCP proxy
│   ├── PortWatcher.swift             # Port monitoring
│   ├── FavoritesManager.swift        # Favorites
│   └── HistoryManager.swift          # Kill history (thread-safe)
├── PortKillerCLI/              # CLI tool
│   ├── CLI.swift                     # Argument parsing
│   └── InteractiveMode.swift         # Basic interactive mode
└── Fonts/                      # Drop .ttf/.otf here for custom fonts
```

## Tech Stack

- **Swift 5.9** + **SwiftUI** — native macOS UI
- **AppKit** — menu bar, NSWindow management
- **TerminalTUI** — custom zero-dependency TUI engine (ANSI rendering, key handling, widget system)
- **Network.framework** — TCP proxy (NWListener + NWConnection)
- **CoreText** — runtime font registration from custom font files
- **proc_pidpath** — process classification via executable path (with bounds-checked buffer)
- **Thread safety** — NSLock on shared caches; process execution with 10s timeout

### Using TerminalTUI in Your Own Project

`TerminalTUI` is a standalone, zero-dependency Swift library. Add it to your `Package.swift`:

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
        screen.put(row: 0, col: 0, text: "Hello, TUI!", style: ANSI.bold + ANSI.fg(.cyan))
    }
    mutating func handleKey(_ key: KeyEvent) -> ScreenAction {
        key == .char("q") ? .quit : .continue
    }
}

let app = TUIApp(screen: MyScreen())
app.run()
```

## License

MIT — see [LICENSE](LICENSE) for details.

---

<p align="center">&copy; Srinivas Pendela 2024–2026. All rights reserved.</p>
