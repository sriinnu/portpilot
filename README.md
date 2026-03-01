# PortPilot

<p align="center">
  <img src="assets/portpilot.svg" alt="PortPilot" width="128" height="128">
</p>

<h3 align="center">Beautiful port management for macOS</h3>

<p align="center">
  Monitor, manage, and kill port processes from your menu bar and a full-featured window — with first-class support for SSH, Kubernetes, and Cloudflare tunnels.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0%2B-brightgreen?style=flat-square" alt="macOS 13.0+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" alt="MIT License">
</p>

---

## Why PortPilot?

Port conflicts kill developer flow. PortPilot gives you instant visibility into every listening port on your Mac — and the power to kill any of them in one click.

Unlike basic `lsof` wrappers, PortPilot understands **tunnels**. It detects SSH forwards, `kubectl port-forward`, and Cloudflare tunnels, showing you meaningful names like `meilisearch` instead of raw `kubectl`.

## Features

### Menu Bar Dropdown
- Live port list grouped by connection type (Local, SSH, Kubernetes, Cloudflare)
- Color-coded sections with tunnel-aware labels
- Inline **Stop** button on tunnel rows — no hover required
- K8s namespace sub-grouping when ports span multiple namespaces
- Search, protocol filter, tree/list toggle

### Main Window
- Full port list with type icons and tunnel names
- **Configuration panel** — connection details, editable names, port mapping visualization
- **3-box port mapping** for tunnels: `Remote(:8080)` → `Local(:3000)` → `Protocol(TCP)`
- **Connection naming** — name any port, persisted across sessions
- **Per-port log filtering** — toggle a funnel icon to see only the selected port's logs
- Favorites, categories (Web, Database, Dev, System), bulk kill

### CLI Tool
```bash
# List all ports
portpilot list

# Filter by range and protocol
portpilot list --start 3000 --end 3999 --proto tcp

# JSON output
portpilot list --json

# Kill a port
portpilot kill 5173 --force

# Interactive mode
portpilot interactive
```

## Installation

### Build from Source

```bash
git clone https://github.com/sriinnu/portpilot.git
cd portpilot

# Build release
swift build -c release

# Copy app to Applications
cp -r .build/release/PortPilot.app /Applications/
```

### Requirements
- macOS 13.0+
- Xcode 15.0+ / Swift 5.9+ (build only)

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+R` | Refresh ports |
| `Cmd+F` | Search |
| `Cmd+,` | Settings |
| `Delete` | Kill selected port |

## Architecture

```
Sources/
├── PortPilot/              # SwiftUI macOS app
│   ├── PortPilotApp.swift        # App entry point
│   ├── ContentView.swift         # Main window layout
│   ├── PortViewModel.swift       # Core state + tunnel detection
│   ├── MenuBarDropdownView.swift # Menu bar popup
│   ├── MenuBarController.swift   # Status item management
│   ├── PortListPanel.swift       # Port list sidebar
│   ├── ConfigurationPanel.swift  # Port detail + mapping
│   ├── LogsPanel.swift           # Activity logs
│   ├── Theme.swift               # Colors, icons, sizes
│   ├── SettingsView.swift        # Preferences
│   └── AppSettings.swift         # UserDefaults wrapper
├── PortManagerLib/         # Shared library
│   ├── PortManager.swift         # lsof/kill operations
│   ├── PortWatcher.swift         # Port monitoring
│   ├── FavoritesManager.swift    # Favorites persistence
│   └── HistoryManager.swift      # Kill history
└── PortKillerCLI/          # CLI tool
    ├── CLI.swift                 # Argument parsing
    └── InteractiveMode.swift     # TUI mode
```

## Tech Stack

- **Swift** + **SwiftUI** — native macOS UI
- **AppKit** — menu bar integration
- **Swift Package Manager** — build system

## License

MIT — see [LICENSE](LICENSE) for details.

## Acknowledgments

Inspired by [PortKiller](https://github.com/nicepkg/port-killer).
