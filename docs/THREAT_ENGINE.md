# Threat Engine v1 — Architecture & Operator Guide

PortPilot assesses connection snapshots against five behavioral rules and a
learning baseline, notifying for novel signals. Findings are investigation
prompts, not malware verdicts or proof of an attack. No findings is not proof
of safety; keep existing firewall and endpoint protections enabled.

Operator precautions: [mission.md](../mission.md). Contributor invariants:
[AGENTS.md](../AGENTS.md). In the app, open **Settings → Security FAQ** or the
**Security FAQ** button in Security Center. The FAQ is local, read-only help.

## The one idea

> Detection without memory is just a threshold. Memory without restraint is
> just spam. The engine keeps both: a baseline of "normal" and a cooldown
> per signal.

## Signal catalog (v1 rules)

| # | Signal | Severity | Default threshold | Observed pattern (not attribution) |
|---|--------|----------|-------------------|------------------|
| 1 | `blocklistedRemote` | critical | your alert list | listed endpoint contact |
| 2 | `highConnectionCount` | warning | > 50 / process | high connection volume |
| 3 | `remoteFanout` | warning | ≥ 15 distinct remotes on one local port | many remote endpoints |
| 4 | `newRemoteBurst` | warning | ≥ 10 unseen remotes for a known executable identity | unfamiliar endpoint burst |
| 5 | `firstSeenDialer` | info | unknown executable identity, ≥ 5 conns | first-seen executable with connections |

Rule 2 preserves the legacy "suspect" (>50) definition exactly — enabling
the engine never redefines an existing alert. Rules 4–5 are
baseline-relative and stay silent until one complete snapshot initializes the
baseline. New executable identities and remotes remain candidates until they
recur in a second complete snapshot. Absolute blocklist/count/fan-out findings
still surface immediately on the first snapshot.

## File map

```
Sources/PortManagerLib/
├── ThreatModels.swift      # Vocabulary: severity, signal types, finding,
│                           #   assessment, configuration, baseline. No I/O.
├── ThreatDetector.swift    # Pure rules. Static, no singletons, injectable
│                           #   blocklist closure. Add a rule = new case +
│                           #   one method + one call site.
├── ThreatHistoryStore.swift # Capped JSON ring (~/.portpilot/threat-history.json)
│                           #   sampled history, not a complete audit trail.
└── BlocklistStore.swift    # Single owner for blocklist reads AND edits
                            #   (comments preserved on write).

Sources/PortKillerCLI/
├── BlocklistCommand.swift  # `portpilot blocklist list|add|remove`
└── CLI.swift               # `connections --threats`, `connections --watch N`

Sources/PortPilotTUI/
└── PortListScreen.swift    # `!` threats-only filter in Connections tab

Sources/PortPilot/
├── Stores/ThreatMonitorStore.swift # Background poll → detect → learn →
│                                   #   page-if-novel. Cooldowns + coalesced
│                                   #   summary notification. Mirrors the
│                                   #   PortGuardStore threading pattern.
├── SecurityCenterView.swift        # Incident list: status header, severity
│                                   #   chips, finding cards (Kill/Freeze/Copy/
│                                   #   Flag host), tuning, history, FAQ entry.
├── SecurityFAQView.swift           # Local searchable precautions, also in Settings.
└── Theme.swift (Severity)  # FIXED semantic colors — urgency survives every
                            #   visual theme by refusing palette derivation.
```

## Data flow (macOS app)

```
lsof/ss ──▶ getAllConnections() ──▶ ThreatDetector.assess()
      (15s poll, utility queue)        │  baseline diff
                                       ▼
                              ThreatAssessment ──▶ baseline.advanceSnapshot()
                                       │           history.record()
                                       ▼
                              novel? (cooldown) ──▶ ONE summary notification
                                       │           + activity-log entries
                                       ▼
                              Security Center renders findings
                              menubar turns red on critical
```

## Anti-spam contract

1. First tick surfaces absolute rules; baseline-relative candidates quarantine
   until a later complete snapshot confirms them.
2. A signal notifies at most once per cooldown (default 15 min).
3. Simultaneous novel signals coalesce into one banner; detail lives in the
   Security Center, never in a banner stack.
4. Muting PortPilot mutes banners, never tracking — the Center stays live.
5. Info findings never touch the menubar; they merit a look, not a buzz.

## Operator usage

```bash
# One-shot assessment (same engine as the app)
portpilot connections --threats
portpilot connections --threats --json | jq '.[].processName'

# Headless auto-alert for servers (new baseline identities quarantine first)
portpilot connections --watch 15

# Blocklist management without opening an editor mid-incident
portpilot blocklist add 203.0.113.9
portpilot blocklist add .evil.com
portpilot blocklist remove 203.0.113.9
```

TUI: Connections tab → `!` toggles threats-only (composes with `/` search).
App: sidebar Security tab → Kill / Freeze (SIGSTOP, reversible) /
Copy remote / Flag host, plus threshold tuning and recent history. “Flag host”
adds a detection rule; it does not deny packets or close connections. Existing
matcher caches may take up to 60 seconds to refresh. Domains are not resolved
into IPs for matching; blocklist CIDRs are IPv4-only (exact IPv6 is supported).

## Known limits (honest)

- `lsof`/`ss` see **established** connections only. SYN floods and scans
  that never complete are invisible to v1 — that needs firewall-log tailing
  (documented v2 source).
- No GeoIP/reputation feeds yet — blocklist + behavior only.
- Snapshot failures retain the last successful assessment and do not advance
  learning. Pending, paused, degraded, and filtered-empty views are not clean states.
- Identity is user/path (PID-scoped fallback), not a signature/hash. Learning is
  session-memory; repeated malicious behavior can still normalize.
- Threat findings do not automatically quarantine processes. Separately enabled
  Port Guard can terminate later holders on configured ports, even with threat
  monitoring paused. Reserved ports only warn; they do not prevent kills.
- Persisted history is capped and may include private endpoints, process/user
  metadata, or cron commands. Cron output stays in memory, with excerpts in the
  live Activity Log, not the cron history file. Private modes are not encryption.

## Roadmap

- **v2:** GeoIP + rDNS enrichment, `pf`-log scan detection, finding
  resolution states (acknowledged/allowlisted/blocked), `portpilot watch`
  as a launchd daemon with webhook export.
- **v3:** per-hour statistical baselines with decay, process-lineage
  signals (who spawned the dialer), SIEM export.
