# PortPilot Usage Reference

Operational reference for PortPilot: the `portpilot` CLI, the `portpilot-tui` terminal UI, and the macOS menu bar app. Covers common tasks, exact commands, and integration patterns for scripts, CI, and agents.

Build and installation instructions: [README.md](README.md). Source tree and internals: [ARCHITECTURE.md](ARCHITECTURE.md).

## When to use PortPilot

| Task | Command |
|------|---------|
| Port conflict: find and kill what holds a port | `portpilot kill 3000` |
| List everything listening (ports + Unix sockets) | `portpilot list` / TUI Sockets tab |
| Find active tunnels (SSH forwards, kubectl, Cloudflare) | TUI Ports tab (TYPE column); menu bar dropdown List View groups by connection type |
| Check whether a local daemon is running | TUI Sockets tab (PID + socket path) |
| Inspect established connections by process | `portpilot connections` |
| Free a port range before starting services | `portpilot find --start 8000 --end 8999` |

## CLI reference

### List ports

```bash
portpilot list                          # all listening ports
portpilot list --start 3000 --end 9999  # port range
portpilot list --proto tcp              # protocol filter (tcp/udp)
portpilot list --json                   # JSON output
```

`--json` fields: `port`, `protocolName`, `pid`, `user`, `command`, `fullCommand`, `parentPID`, `startTime`, `workingDirectory`, `processPath`, `socketPath`, `cpuUsage`, `memoryMB`.

### Kill processes

```bash
portpilot kill 3000            # SIGTERM the process on the port
portpilot kill 3000 --force    # SIGKILL
portpilot kill :8080           # colon prefix accepted
portpilot kill-all             # every listed process
```

`kill` exits non-zero if processes survive SIGKILL (`partialKill` error lists the surviving PIDs).

### Get PIDs

```bash
portpilot pid 8080            # "Port 8080 -> PID 12345"
portpilot pid -q 8080         # "12345" only (--quiet)
portpilot pids 3000 3001 3002 # one "Port <port> -> PID <pid>" line per port
```

When no process is found, `pid` prints "No process found listening on port N" (nothing with `--quiet`) and exits 1, which makes it usable as a shell test.

### Find free ports

```bash
portpilot find --start 8000 --end 8999
```

### Connections

```bash
portpilot connections               # established connections grouped by process
portpilot connections --suspect     # only processes with >50 connections
portpilot connections --blocklist   # only blocklisted remote hosts
portpilot connections --kill 12345  # kill by PID
portpilot connections --json
```

### Cronjobs

```bash
portpilot cronjobs                 # user crontab + system cron
portpilot cronjobs --user-only
portpilot cronjobs --system-only
portpilot cronjobs --json
```

### Programs and Docker

```bash
portpilot program-pids --program node
portpilot program-kill --program node
portpilot docker                   # Docker containers behind ports
```

### SOCKS proxy

```bash
portpilot proxy --port 1080 --ssh user@host
```

Wraps `ssh -D 1080 -N user@host`. `--pid-file <path>` writes the SSH PID; `--verbose` passes SSH output through. Stops on Ctrl+C.

### Interactive modes

```bash
portpilot interactive   # basic interactive kill mode
portpilot tui           # full TUI (same as portpilot-tui)
```

## TUI

```bash
portpilot-tui
```

Tabs: Ports, Sockets, Schedules, Connections.

| Key | Action |
|-----|--------|
| `↑↓` / `j` `k` | Navigate |
| `Enter` | Kill process (confirmation prompt: `y`/`n`) |
| `/` | Search / clear filter |
| `Tab` | Switch tab |
| `i` | Process detail view (info + connections) |
| `r` | Refresh |
| `q` | Quit |

Requires a POSIX terminal (macOS, Linux, WSL). Not supported on native Windows.

## macOS app operations

Menu bar dropdown:

| Action | How |
|--------|-----|
| Open dropdown | Click the menu bar icon |
| Filter by protocol | All / TCP / UDP chips |
| Switch grouping | List View (by connection type) / Tree View (by process) toggle |
| View cronjobs | Schedules section (read-only list) |
| Kill a process | Hover a row, click the kill action |
| Open main window | "Open PortPilot App" at the bottom |

Main window:

| Action | How |
|--------|-----|
| Select port | Click a row in the port list |
| Inspect process | Configuration panel shows PID, path, working directory, CPU, uptime, connections |
| Start/stop TCP proxy | Configuration panel → Quick Proxy → set target port → Start/Stop |
| Filter | Protocol and type filters in the sidebar; system-process toggle in the toolbar |
| Kill process | Kill action on the selected port |
| Cronjob controls | Schedules section: pause/resume (personal crontab only, stored with a recoverable marker), Run Now, Stop, run history. System cron entries are read-only. |

## Integration patterns

### Agents and scripts

```bash
# Structured port data
portpilot list --json | jq '.[] | select(.port == 3000)'

# Test whether a port is in use before starting a server
portpilot pid 3000 && echo "Port 3000 is occupied" || echo "Port 3000 is free"

# Kill and verify
portpilot kill 3000 && sleep 1 && (portpilot pid 3000 || echo "Port freed")

# What occupies a port range
portpilot list --start 8000 --end 8999 --json | jq '.[].command'
```

### CI

```bash
# Fail if test servers survived the suite
leftover=$(portpilot list --start 3000 --end 9999 --json | jq length)
if [ "$leftover" -gt 0 ]; then
  echo "WARNING: $leftover ports still occupied after tests"
  portpilot list --start 3000 --end 9999
  exit 1
fi
```

### Makefile

```makefile
.PHONY: dev clean-ports

clean-ports:
	@portpilot kill 3000 2>/dev/null || true
	@portpilot kill 5173 2>/dev/null || true

dev: clean-ports
	npm run dev
```

## Behavior notes

### Process classification

Processes are classified from the executable path (`proc_pidpath` on macOS), evaluated in this order:

1. Basename in the known system-daemon set (`launchd`, `WindowServer`, `mDNSResponder`, ...) → System
2. Basename in the known dev-command set (`node`, `python3`, `go`, `docker`, `kubectl`, `postgres`, `redis-server`, `nginx`, `ssh`, `cloudflared`, ...) → Developer. Checked before path prefixes so dev tools living in `/usr/bin` are not classified as System.
3. Path prefix `/opt/homebrew/`, `/usr/local/bin/`, `/usr/local/opt/`, `/usr/local/Cellar/` → Developer
4. Path prefix `/System/`, `/usr/libexec/`, `/usr/sbin/`, `/sbin/`, `/usr/bin/`, `/Library/Apple/` → System
5. Path contains `.app/` or starts with `/Applications/` → App
6. Path starts with the user's home directory → App
7. Otherwise → Other

### Port and connection discovery

| Platform | Source |
|----------|--------|
| macOS, TCP/UDP listeners | `lsof -iTCP -iUDP -sTCP:LISTEN -P -n` |
| macOS, Unix sockets | `lsof -U -P -n` |
| macOS, process path | `proc_pidpath()` |
| macOS, full command / parent / start time | `ps -p <pids> -o pid=,ppid=,lstart=,args=` |
| macOS, working directory | `lsof -w -a -p <pids> -d cwd -F pn` |
| Linux / WSL | `ss -tulnp` |
| Windows | `netstat -ano` + `tasklist /FO CSV /NH` |

Process execution has a 10-second timeout; shared caches are NSLock-guarded.

### Blocklist

`~/.portpilot/blocklist.txt`, one entry per line: domain, domain suffix (leading `.` matches subdomains), IP, IPv6 prefix, or CIDR range. Matching connections are flagged by `portpilot connections`, the TUI Connections tab, and the menu bar app. The file is cached for 60 seconds.

## Requirements

- macOS app: macOS 13.0+, Xcode 15+, Swift 5.9+
- CLI / TUI: Swift 5.9+ on any supported platform
- npm scripts: Node.js 18+
