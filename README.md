# PortPilot

<p align="center">
  <img src="assets/portpilot.svg" alt="PortPilot" width="128" height="128">
</p>

<h3 align="center">Port management from your menu bar</h3>

<p align="center">
  Monitor ports, discover local app daemons, proxy traffic, and kill processes — all from the macOS menu bar. With first-class support for SSH, Kubernetes, and Cloudflare tunnels.
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
- **CPU usage** — real-time per-process CPU % with color-coded badges (green/yellow/orange/red)
- **Filter pills** — TCP / UDP / Unix protocol filters, connection type icons with counts, hide system toggle
- **Process classification** — each process labeled as System, App, or Developer using `proc_pidpath`
- **Tunnel detection** — SSH, Kubernetes, Cloudflare with smart name extraction
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

### CLI Tool (Cross-Platform)
```bash
portpilot list                          # All listening ports (with CPU%)
portpilot list --start 3000 --end 9999  # Port range
portpilot list --proto tcp --json       # JSON output (includes cpuUsage)
portpilot kill 5173 --force             # Kill by port
portpilot kill :8080                    # Colon prefix syntax
portpilot pid 8080                      # Get PID for port
portpilot pids 3000 3001 3002           # Multiple PIDs
portpilot interactive                   # TUI mode
portpilot proxy --port 1080 --host user@server  # SOCKS proxy
```

CLI table output now includes a CPU% column:
```
PORT     PROTO  PID      CPU%     USER               COMMAND
3000     TCP    21082    0.0      user               node
5432     TCP    63341    9.4      user               OrbStack
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

### macOS (App + CLI)
```bash
git clone https://github.com/sriinnu/portpilot.git
cd portpilot
npm run release
```

This builds everything and installs:
- `PortPilot.app` → `/Applications/` (menu bar app)
- `portpilot` CLI → `/usr/local/bin/`

Then just use it:
```bash
portpilot list              # list all listening ports
portpilot kill 3000         # kill process on port 3000
portpilot list --json       # JSON output for scripting
```

### Linux / WSL
```bash
git clone https://github.com/sriinnu/portpilot.git
cd portpilot
swift build -c release
sudo cp .build/release/portpilot /usr/local/bin/
```

Works out of the box — uses `ss` under the hood:
```bash
portpilot list              # all listening ports
portpilot kill 8080         # kill by port
portpilot pids 3000 3001    # get PIDs
portpilot interactive       # TUI mode
```

### Windows
Requires [Swift for Windows](https://www.swift.org/install/windows/):
```powershell
git clone https://github.com/sriinnu/portpilot.git
cd portpilot
swift build -c release
copy .build\release\portpilot.exe "C:\Program Files\PortPilot\"
```

Uses `netstat` + `tasklist` automatically:
```powershell
portpilot list              # all listening ports
portpilot kill 5000 --force # force kill
portpilot list --json       # pipe to tools
```

> **No config, no setup, no runtime dependencies.** Platform detection is automatic — same CLI interface everywhere.

### npm scripts (macOS)
```bash
npm run build        # Build app only
npm run build:cli    # Build CLI only
npm run dev          # Build debug + launch
npm run open         # Open installed app
npm run uninstall    # Remove from /Applications
npm run reinstall    # Clean reinstall
npm run clean        # Remove build artifacts
```

## Platform Support

| Platform | GUI App | CLI | Port Discovery | Install |
|----------|---------|-----|---------------|---------|
| macOS 13+ | Menu bar + window | `portpilot` | `lsof` + `proc_pidpath` | `npm run release` |
| Linux | - | `portpilot` | `ss` | `swift build -c release` |
| WSL | - | `portpilot` | `ss` | `swift build -c release` |
| Windows | - | `portpilot` | `netstat` + `tasklist` | `swift build -c release` |

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+R` | Refresh ports |
| `Cmd+F` | Search |
| `Cmd+,` | Settings |

## Architecture

```
Sources/
├── PortPilot/                  # macOS menu bar app
│   ├── PortPilotApp.swift            # Pure AppKit entry (no Dock icon)
│   ├── ContentView.swift             # Main window layout
│   ├── PortViewModel.swift           # State, filtering, tunnel detection
│   ├── MenuBarController.swift       # Status item + panel management
│   ├── MenuBarDropdownView.swift     # Dropdown with Ports/Sockets tabs
│   ├── MenuBarPanel.swift            # Floating NSPanel
│   ├── PortListPanel.swift           # Port list with classification badges
│   ├── ConfigurationPanel.swift      # Config + proxy controls
│   ├── MainWindowToolbar.swift       # Toolbar with filter pills
│   ├── LogsPanel.swift               # Activity logs
│   ├── Theme.swift                   # 5 color themes (Classic, Graphite, Sunset, Oceanic, Noir)
│   ├── FontManager.swift             # Custom font loading from Fonts/ folder
│   ├── SettingsView.swift            # Preferences (appearance, fonts, themes)
│   └── AppSettings.swift             # UserDefaults + font/theme settings
├── PortManagerLib/             # Shared library
│   ├── PortManager.swift             # Port + socket + CPU discovery
│   ├── ProcessClassifier.swift       # proc_pidpath classification
│   ├── TCPProxyManager.swift         # Network.framework TCP proxy
│   ├── PortWatcher.swift             # Port monitoring
│   ├── FavoritesManager.swift        # Favorites
│   └── HistoryManager.swift          # Kill history (thread-safe)
├── PortKillerCLI/              # CLI
│   ├── CLI.swift                     # Argument parsing
│   └── InteractiveMode.swift         # TUI mode
└── Fonts/                      # Drop .ttf/.otf here for custom fonts
```

## Tech Stack

- **Swift 5.9** + **SwiftUI** — native macOS UI
- **AppKit** — menu bar, NSWindow management
- **Network.framework** — TCP proxy (NWListener + NWConnection)
- **CoreText** — runtime font registration from custom font files
- **proc_pidpath** — process classification via executable path (with bounds-checked buffer)
- **Thread safety** — NSLock on shared caches; process execution with 10s timeout

## License

MIT — see [LICENSE](LICENSE) for details.

---

<p align="center">&copy; Srinivas Pendela 2024–2026. All rights reserved.</p>
