# Security measures

PortPilot is a local user-session utility with deliberate access to process,
connection, cron, Docker, and proxy controls. Its security model is simple:
stay under the logged-in user, fail visibly when observations are incomplete,
and recheck identity before changing system state.

This page summarizes the current source-level protections. It is not a claim
that a local build is signed, notarized, installed, or validated on Windows.

## Runtime authority

- The app, CLI, and TUI run as the logged-in user. PortPilot does not require or
  recommend a root runtime to improve monitoring visibility.
- Main-window actions use existing OS-user authority. PortPilot does not add a
  remote admin API or a separate application authentication boundary.
- Kill, freeze, resume, Guard, cron, Docker, packet-capture, and proxy actions
  are treated as real external effects and require deliberate user controls.

## Honest observations

- Command launch failure, timeout, nonzero exit, and truncated output are not
  treated as successful empty discovery.
- Pending, paused, degraded, stale/last-good, filtered-empty, and
  latest-successful-empty states remain distinct in the UI.
- Failed connection or alert-list enrichment does not advance threat-learning
  baselines. The main connection UI keeps the last successful observations and
  marks them stale; the menubar reports degradation and metrics do not record
  cached counts as fresh samples.
- Threat findings are heuristics, not malware verdicts. New identities and
  remotes require repeated complete snapshots before baseline promotion;
  absolute rules still run on the first complete snapshot.
- Stale threat findings do not drive current menubar alerts. Only a current
  assessment may page; fresh critical evidence still outranks degradation in
  an unrelated observation source.

## Process-action safety

- Cached process actions carry a captured start identity. PortPilot rechecks
  the current PID incarnation before every signal and escalation.
- PID 0 and PID 1 are invalid targets. A missing or changed identity refuses
  the action, and permission failure is not reported as process exit.
- Guard uses per-port lifecycle generations. Disarming invalidates pending
  enforcement and escalation attempts; re-enabling does not revive old work.
- Only confirmed receipts justify a “stopped” result.

## Cron safety

- Cron discovery uses checked reads and distinguishes a confirmed absent user
  crontab from discovery failure or partial system-source access.
- A retained last-good schedule list is inspect-only while discovery is
  incomplete. Run Now and schedule edits remain disabled until a complete read.
- Edits use complete reads, exact duplicate selection, a shared edit lock, a
  conflict reread, private temporary files, and fail-closed installation.
- Run Now deliberately executes the selected command through `/bin/sh -c` with
  user authority. Captured output is limited to 256 KiB and a manual run has a
  one-hour deadline.
- Stopping descendants is best effort. Detached children and independently
  scheduled OS cron runs are outside the manual-run guarantee.

## Proxy and network boundaries

- App Quick Proxy defaults to IPv4 loopback.
- LAN exposure is explicit and source-CIDR gated. IPv4 and IPv6 `/0` policies
  are rejected; narrow `/32` or `/128` client entries are preferred.
- Admission caps, idle deadlines, port validation, and idempotent cleanup bound
  listener behavior.
- Source CIDRs are not authentication, encryption, or proof that traffic
  arrived through a physical LAN interface. Keep the target service’s own
  authentication and TLS, and do not add router forwarding casually.
- CLI `proxy` uses OpenSSH SOCKS and has a different control path.

## Alert list and private storage

- `~/.portpilot/blocklist.txt` is an alert list, not a firewall. It annotates
  observations and never claims to block traffic.
- Alert-list reads distinguish missing from unreadable or corrupt. Failed reads
  degrade monitoring instead of becoming a cached empty policy.
- Sensitive POSIX files use mode `0600`; app-owned private directories use
  `0700`. Replacements are atomic and shared mutations use cross-process locks.
- Cron commands and captured output can contain secrets. Permissions reduce
  cross-account exposure but are not encryption or Windows ACL enforcement.

## Release integrity

- Release handoff requires an audited `main`, a verified signed commit, and a
  verified annotated signed tag pointing to that exact revision.
- Artifacts must have an intact Developer ID Application signature from the
  configured team. The app, CLI, and TUI must carry hardened runtime on every
  Mach-O architecture.
- Release policy rejects known hardened-runtime exception entitlements on each
  checked architecture, including disabled library validation, unsigned
  executable memory, JIT, debugger, and task-inspection exceptions.
- Release wrappers preserve failures and create only a local handoff. Signing a
  local build does not mean it is notarized, installed, or published.

## Important limits

- PortPilot is not a firewall, endpoint-protection product, or malware scanner.
- Connection snapshots are periodic and permission-limited; they are not packet
  enforcement and can miss short-lived activity.
- Learning is not trust. Persistent malicious behavior can normalize, and
  baselines are session memory rather than durable approval.
- User-space PID validation cannot close the final kernel check-to-signal race.
- CIDR policy can still be made dangerously broad without using `/0`; review
  every allowed source range.
- Native Windows support is planned/partial and does not yet have macOS parity.

## Operator checklist

1. Keep Guard disarmed until the displayed port and current process identity
   have been reviewed.
2. Treat a degraded or stale observation as unknown, not clean; fix the read
   failure and refresh.
3. Review cron commands before Run Now. They execute as your user.
4. Keep Quick Proxy on loopback unless LAN access is required. If enabled, use
   the narrowest client addresses and retain target-service auth/TLS.
5. Keep existing firewall and endpoint protections enabled.
6. Before distributing a build, run the repository tests and release-policy
   checks, then separately complete signing, notarization, and installed/live
   acceptance as required.

## Evidence and deeper detail

- [Current Daybreak audit](../DAYBREAK_SECURITY_AUDIT_2026-10-29.md)
- [Threat model](../../ports-threat-model.md)
- [Threat-engine behavior](../THREAT_ENGINE.md)
- [Security review and safe reproductions](../SECURITY_REVIEW_2026-10-22.md)
- [Product boundaries and operator precautions](../../mission.md)

Last source review: 2026-10-29.
