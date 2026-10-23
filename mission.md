# PortPilot mission

Make local ports, processes, connections, and cron jobs understandable and
deliberately controllable, without quietly widening the user's privileges or
network exposure.

The product is a macOS app plus CLI/TUI with a shared Swift core. Linux support
exists in selected CLI paths. Windows is a future/partial target, not a current
security-parity promise.

## Product boundaries

PortPilot inventories local OS state, highlights behavioral signals, and offers
explicit control actions. Those actions run with the current user's authority.
It is not an antivirus, endpoint security replacement, full protocol/payload inspector,
firewall, privileged service manager, or authenticated remote-administration API.
Keep existing OS, firewall, and endpoint protections enabled.

The macOS app also offers explicit, bounded per-port packet-summary capture
using the system tcpdump tool. It is off by default, requires existing user
capture-device access, and does not install a privileged helper. It prints
numeric endpoint/protocol summaries without payload display or capture files.
A port filter is not process attribution; other processes and transit traffic
can match. The threat detector still uses periodic connection snapshots rather
than these manually requested packet observations.

| Boundary | What crosses it | Required precaution |
| --- | --- | --- |
| OS → discovery → detector | Permission-limited, periodic connection/process snapshots | Failed or partial discovery is unknown/stale, never clean; no baseline learning from failures. |
| Detector → user | Threshold and baseline findings, summaries, notifications | Heuristic evidence, not a malware verdict. No findings does not prove safety. |
| User → OS effects | Signals, Guard evictions, cron edits/runs/stops, Docker actions | Confirm current target identity and intent; do not test against real services or jobs. |
| Network peer → app Quick Proxy → target | Raw TCP under an optional source-IP policy | Loopback by default; opt-in narrow CIDRs plus target authentication/encryption. |
| Memory → local disk | Alert list, sampled threat history, cron metadata keyed by full command | Private POSIX modes, bounded data, no secrets in commands, redacted sharing. |
| Source → installed product | Builds, tests, packaging, platform adapters | Source-level proof does not establish installed/live or cross-platform security. |

## Alerts and operator precautions

- **Read status before findings.** Pending first check, paused, failed/stale,
  and a successful snapshot with no findings are different states. Periodic
  established-connection discovery can miss short-lived activity, incomplete
  scans, and processes hidden by OS permissions.
- **Interpret severity correctly.** Critical is an alert-list match; Warning
  is a volume/fan-out/new-remote threshold; Info can be a first-seen dialer.
  Legitimate activity can trigger all of these. Investigate before acting.
- **No banner is not no finding.** Notification permission, mute settings,
  coalescing, and the default 15-minute cooldown affect banners. Check Security
  Center directly. Disabling Monitor is different from muting notifications.
- **Learning does not approve software.** New identities/remotes need repeated
  complete snapshots. The user/path identity is not a signature/hash, and repeated
  malicious behavior can become familiar. Learning resets when PortPilot quits
  or restarts, not merely when a monitored program restarts.
- **“Blocklist” means detection only.** It does not deny packets or close
  connections. Domains are not resolved to IPs for matching; IPv4 CIDRs and exact
  IPv6 addresses are supported, not IPv6 CIDRs. Existing matchers cache for up to
  60 seconds. Use a real firewall/service policy for traffic enforcement.
- **Process actions can hurt.** Verify current PID/path/user; a stale PID can
  identify something else. Kill can escalate to SIGKILL and lose unsaved work;
  Freeze leaves sockets and locks held. Reserved ports only warn. Guard
  grandfathers current holders and can kill later holders on configured ports,
  independently of the threat-monitor toggle; review guards separately.
- **Runtime is unprivileged.** Do not run the app/CLI as root to increase visibility.
  Main-window actions rely on the OS user, not a separate application login.
- **Require a result, not a hopeful button.** Cached process actions are bound to
  the observed process incarnation and refuse changed/unavailable identities.
  Permission failures and survivors are not successful stops. Guard only arms
  after complete discovery, with independent per-port setup; this remains
  best-effort user-space enforcement, not an atomic kernel security boundary.
  Disarm invalidates pending enforcement/escalation generations; it cannot undo
  signals already delivered, and re-enable must not revive the old attempt.
- **Check startup and delivery.** Launch at login must show actual macOS status,
  pending approval and errors. A successful local build is not an installed or
  post-login monitoring test; release scripts must not hide failed commands.

## LAN access decision

Local monitoring does not need an inbound network listener. App Quick Proxy binds
to IPv4 loopback (`127.0.0.1`) by default. Enable selected-client sharing only when
needed, using actual client addresses or the narrowest subnet: /32 for one IPv4
client, /128 for one IPv6 client. Do not choose `0.0.0.0/0` or `::/0`.

LAN mode listens across interfaces and filters the peer's source IP; it is not
guaranteed “LAN-only”. VPN routes, NAT, DHCP reuse, and other interfaces can change
who matches. Loopback is not implicitly included in a custom policy. Keep router
port forwarding off, keep the target service's own login/TLS enabled, and stop
unused proxies. CIDRs are not person/device authentication or encryption.

Default Quick Proxy limits are 64 active connections per session and a 300-second
data-idle timeout. They reduce resource pressure, not all denial-of-service risk.
CLI `portpilot proxy` instead launches OpenSSH SOCKS; its authentication, binding,
and lifetime depend on OpenSSH/config and do not inherit Quick Proxy's controls.

## Cron and sensitive data

Run Now executes the saved command through `/bin/sh -c`, unsandboxed, as the
current user. Inspect the command and scripts first. Manual runs retain at most
256 KiB of output and time out after one hour. Stop/timeout cleanup is best-effort;
detached work can escape, so verify completion. These bounds do not constrain
independently scheduled OS cron jobs. The app's Stop action also attempts to
signal independently launched processes matching the job command; verify the
target to avoid collateral effects. Pausing/resuming a job rewrites the real user
crontab; system cron entries are read-only in this product.

Crontab edits reject partial/failed reads, select the exact duplicate occurrence,
serialize PortPilot writers and compare a second read before installation.
An independent editor can still race after that comparison because `crontab`
offers no atomic compare-and-swap. Concurrent alert-list edits use a private
shared transaction lock as well as atomic file replacement.

The alert list and capped threat history live under `~/.portpilot`; cron run
history lives in user Application Support/PortPilot. History may contain process
names, users, remote endpoints, timestamps, and full cron commands (in job keys).
Captured cron output is bounded in memory, not persisted in cron run history;
excerpts can appear in the live Activity Log and shared screenshots/clipboard.
POSIX sensitive files use 0600 and app-owned directories 0700. This is
not encryption, same-account/root isolation, backup protection, or Windows ACL
enforcement. Keep secrets out of command arguments/output and redact diagnostics
before sharing.

## Delivery and acceptance gates

- Preserve regressions for domain-boundary matching, first-snapshot absolute
  alerts, baseline quarantine/identity, failed/truncated discovery, private
  atomic persistence, and bounded cron output/runtime.
- Check loopback/default policy, CIDR rejection/admission, connection limits,
  idle cleanup, and invalid ports using owned local fixtures only.
- Build the macOS app and CLI, run shared-core tests, and keep the Xcode and
  SwiftPM source/import models working. Do not fetch dependencies or touch
  production/third-party systems during the restricted defensive assessment.
- Keep the in-app FAQ available from Settings and Security Center. Warnings
  belong near risky actions too; help text must not contradict button labels.
- Report source/regression, installed/live, and external-effect evidence
  separately. Do not recommend disabling existing protections on a build/test
  result. Windows requires its own authority, process, networking, storage, and
  regression proof before any equivalent-security claim.

Assessment details and source evidence: [ports-threat-model.md](ports-threat-model.md).
Contributor invariants and local verification commands: [AGENTS.md](AGENTS.md).
Detection architecture: [docs/THREAT_ENGINE.md](docs/THREAT_ENGINE.md).
Three-agent follow-up and regression paths:
[docs/SECURITY_REVIEW_2026-10-22.md](docs/SECURITY_REVIEW_2026-10-22.md).

## Signed delivery policy

Only identity-signed releases, signed commits, and signed annotated tags are
accepted. Ad-hoc signatures are internal compilation evidence, not releases.
Finish the source/test audit before delivery: branch → PR → main, then sign and
verify the release tag against that audited main revision. No direct-to-main
release script, lightweight tag, unsigned fallback, automatic installation, or
implicit service publication. Keep unrelated dirty work out of the delivery.

Use the configured local signing identity/agent without exporting private keys.
Developer ID signing does not imply notarization or installed/live acceptance;
Apple notarization and npm publication need separate authorization. GitHub access
for the explicitly requested PR/main workflow is not permission to contact other
systems. Replace old artifacts only after the replacement's signatures and
contents are verified; remove only exact, in-scope artifacts as needed.
