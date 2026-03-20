# PortPilot Skill

> This document describes PortPilot as a learnable skill for humans and AI agents. Use it to understand, operate, and integrate PortPilot into workflows.

## What is PortPilot?

PortPilot is a macOS menu bar app and cross-platform CLI that monitors network ports, discovers local app daemons (Unix sockets), classifies processes, proxies TCP traffic, and kills processes. It replaces manual `lsof`, `kill`, `ss`, and `netstat` commands with a single tool.

## When to use PortPilot

- **Port conflict**: "something is already running on port 3000" → find and kill it
- **Process discovery**: "what's listening on my machine?" → see all ports + sockets
- **Tunnel management**: "which kubectl port-forwards are active?" → grouped view
- **Traffic forwarding**: "proxy port 8080 to port 9090" → native TCP proxy
- **Daemon inspection**: "is my local service running?" → check sockets tab for PID + socket path

## CLI Reference

### List ports
```bash
# All listening ports
portpilot list

# Filter by range
portpilot list --start 3000 --end 9999

# Filter by protocol
portpilot list --proto tcp

# JSON output (for piping to jq, scripts, AI agents)
portpilot list --json
```

**Output fields** (JSON): `port`, `protocolName`, `pid`, `user`, `command`, `fullCommand`, `parentPID`, `startTime`, `workingDirectory`, `processPath`, `socketPath`

### Kill processes
```bash
# Kill by port number
portpilot kill 3000

# Force kill (SIGKILL instead of SIGTERM)
portpilot kill 3000 --force

# Colon prefix syntax
portpilot kill :8080
```

### Get PIDs
```bash
# Single port
portpilot pid 8080
# → 12345

# Multiple ports
portpilot pids 3000 3001 3002
# → 3000: 12345
# → 3001: 12346
# → 3002: 12347
```

### SOCKS proxy
```bash
portpilot proxy --user myuser --host remote-server --port 1080
```

### Interactive mode
```bash
portpilot interactive
```

## GUI Operations (macOS)

### Menu bar dropdown
| Action | How |
|--------|-----|
| Open dropdown | Click menu bar icon (top-right) |
| Switch tabs | Click "Ports" or "Sockets" tab |
| Filter by protocol | Click TCP / UDP / Unix pills |
| Filter by type | Click Local / DB / K8s / CF / SSH icons |
| Hide system processes | Click "Sys" toggle |
| Kill a process | Hover row → click stop/kill icon |
| Copy port info | Hover row → click copy icon |
| Open main window | Click "Open PortPilot" at bottom |
| Refresh | Click "Refresh" or Cmd+R |

### Main window
| Action | How |
|--------|-----|
| Select port | Click in left panel |
| View config | Selected port details appear in right panel |
| Start proxy | In config panel → "Quick Proxy" → set target → "Start Proxy" |
| Stop proxy | Click "Stop" on active proxy, or "Stop All" in bottom-right overlay |
| Filter | Use pill buttons in toolbar |
| Kill process | Click kill icon on port row |
| Search | Type in search field |

## Integration Patterns

### For AI agents
```bash
# Get structured port data
portpilot list --json | jq '.[] | select(.port == 3000)'

# Check if a port is in use before starting a server
portpilot pid 3000 && echo "Port 3000 is occupied" || echo "Port 3000 is free"

# Kill and verify
portpilot kill 3000 && sleep 1 && portpilot pid 3000 || echo "Port freed"

# Find what's using a port range
portpilot list --start 8000 --end 8999 --json | jq '.[].command'
```

### For shell scripts
```bash
#!/bin/bash
# Free up dev ports before starting services
for port in 3000 3001 5173 8080; do
  if portpilot pid $port > /dev/null 2>&1; then
    echo "Killing process on port $port"
    portpilot kill $port
  fi
done
echo "All dev ports free"
```

### For CI/CD
```bash
# Verify no leftover processes after test suite
leftover=$(portpilot list --start 3000 --end 9999 --json | jq length)
if [ "$leftover" -gt 0 ]; then
  echo "WARNING: $leftover ports still occupied after tests"
  portpilot list --start 3000 --end 9999
  exit 1
fi
```

### For Makefiles
```makefile
.PHONY: dev clean-ports

clean-ports:
	@portpilot kill 3000 2>/dev/null || true
	@portpilot kill 5173 2>/dev/null || true

dev: clean-ports
	npm run dev
```

## Process Classification Logic

PortPilot classifies processes using executable path heuristics:

```
/System/*, /usr/libexec/*, /usr/sbin/*, /sbin/*  →  System
/opt/homebrew/*, /usr/local/bin/*                  →  Developer
/Applications/*, *.app/*                           →  App
~/*, /Users/*/                                     →  App
everything else                                    →  Other
```

Known developer commands: `node`, `python`, `ruby`, `java`, `go`, `docker`, `kubectl`, `postgres`, `redis-server`, `nginx`, `ssh`, `cloudflared`, etc.

## Port Discovery Methods

| Platform | Command | Parser |
|----------|---------|--------|
| macOS (TCP/UDP) | `lsof -iTCP -iUDP -sTCP:LISTEN -P -n` | Custom field parser |
| macOS (Unix sockets) | `lsof -U -P -n` | Socket path extractor |
| macOS (process path) | `proc_pidpath()` | Darwin C API |
| macOS (full command) | `ps -p <pids> -o pid=,ppid=,lstart=,cwd=,args=` | Multi-field parser |
| Linux / WSL | `ss -tlnp` | Regex parser |
| Windows | `netstat -ano` + `tasklist /FO CSV` | PID cross-reference |

## TCP Proxy Architecture

Built on Apple's Network.framework:

```
Client → NWListener (listen port) → NWConnection (inbound)
                                          ↕ relay()
                               NWConnection (outbound) → Target (host:port)
```

- Bidirectional data relay with 64KB buffer
- Byte counting per session
- Thread-safe with NSLock on all shared state
- Callbacks dispatched to main thread for UI

## File Structure

```
Sources/
├── PortManagerLib/           # Core library (no UI dependency)
│   ├── PortManager.swift           # lsof/ss/netstat + Unix socket discovery
│   ├── ProcessClassifier.swift     # proc_pidpath + path heuristics
│   ├── TCPProxyManager.swift       # Network.framework proxy
│   ├── PortWatcher.swift           # Poll-based port monitoring
│   ├── HistoryManager.swift        # Kill history persistence
│   └── FavoritesManager.swift      # Favorites persistence
├── PortPilot/                # macOS GUI
│   ├── PortPilotApp.swift          # AppKit entry (NSApplication.run)
│   ├── PortViewModel.swift         # State + business logic
│   ├── MenuBarController.swift     # NSStatusItem management
│   ├── MenuBarDropdownView.swift   # Ports/Sockets tabs
│   ├── ConfigurationPanel.swift    # Detail view + proxy controls
│   └── ...
└── PortKillerCLI/            # Cross-platform CLI
    ├── CLI.swift                   # swift-argument-parser commands
    └── InteractiveMode.swift       # Terminal UI
```

## Requirements

- **macOS app**: macOS 13.0+, Xcode 15+, Swift 5.9+
- **CLI**: Swift 5.9+ (any platform)
- **npm scripts**: Node.js 18+

---

© Srinivas Pendela 2024–2026. All rights reserved.
