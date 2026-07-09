# Architecture

```
Sources/
├── PortPilot/                  # macOS menu bar app (SwiftUI + AppKit)
│   ├── PortPilotApp.swift            # Pure AppKit entry (no Dock icon)
│   ├── ContentView.swift             # Main window layout
│   ├── PortViewModel.swift           # State, filtering, tunnel detection
│   ├── MenuBarController.swift       # Status item + panel management
│   ├── MenuBarDropdownView.swift     # Liquid display dropdown (Top Activity, List/Tree View, Schedules)
│   ├── MenuBarPanel.swift            # Floating NSPanel
│   ├── PortListPanel.swift           # Port list with classification badges
│   ├── ConfigurationPanel.swift      # Config + proxy controls
│   ├── MainWindowToolbar.swift       # Toolbar with filter pills
│   ├── LogsPanel.swift               # Activity logs
│   ├── Theme.swift                   # 6 color themes + Liquid display tokens
│   ├── FontManager.swift             # Custom font loading
│   ├── SettingsView.swift            # Liquid card settings (appearance, fonts, themes)
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
│   └── CronjobDetailScreen.swift     # Cronjob schedule info, next run
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
