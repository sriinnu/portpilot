// main.swift — PortPilot TUI entry point
//
// Launches the terminal UI for managing ports. Cross-platform:
// macOS, Linux, WSL. Uses the TerminalTUI engine (zero dependencies).
//
// Run: swift run portpilot-tui

import Foundation
import TerminalTUI

let app = TUIApp(screen: PortListScreen())
app.refreshInterval = 2.0  // Auto-refresh every 2s for live CPU/memory
app.run()
