# PortPilot contributor guidance

## Scope and evidence

PortPilot is a local user-session port, process, connection, and cron utility:
macOS app, CLI/TUI, and shared `Sources/PortManagerLib`. Windows support is
planned/partial, not validated parity. Read [mission.md](mission.md) for product
boundaries and [ports-threat-model.md](ports-threat-model.md) for the security
assessment, original attack paths, remediations, and verification limits.

- Inspect source and tests before changing behavior. Scanner output, an alert,
  or a plausible attack is not a confirmed vulnerability without a reachable path.
- Preserve existing dirty and untracked work. Keep fixes small; do not rewrite
  history, delete branches, publish, or send externally without explicit direction.
- Separate source/test evidence from installed/live verification and external
  effects. A passing build is not a deployment or proof that a device is safe.
- Assessments and tests stay local. Do not contact production, third-party
  services, or credential stores, and do not fetch packages without authorization.
  Explicit repository delivery authorizes only its GitHub branch/PR/main workflow;
  it does not authorize Apple notarization, npm publishing, or runtime integrations.
  Use configured local signing through the OS/agent without exporting private keys.
- Use `rg` and bounded reads. Avoid generated caches, large logs, dependency
  trees, and real history/credential files in output or commits.

## Security invariants

1. **Least privilege:** app/CLI runtime stays under the logged-in user. Never
   recommend `sudo`/root to improve monitoring visibility. Installation copies
   may need elevation; runtime must not inherit it. Main-window actions use OS
   user authority, not a separate application login boundary.
2. **Honest detection:** findings are heuristics, not malware verdicts. Connection
   snapshots are periodic and permission-limited. Pending, paused, degraded,
   filtered-empty, and latest-successful-empty states must remain distinct.
   Discovery failure, timeout, nonzero status, or truncated output must not be
   interpreted as an empty clean snapshot or advance the learning baseline.
3. **Learning is not trust:** identity is user + executable path with a PID-scoped
   fallback, not a signature/hash. New identities/remotes require repeated complete
   snapshots; absolute rules still run on the first snapshot. Persistent malicious
   behavior can normalize. Baselines are session-memory, not durable approval.
4. **Alert list is not a firewall:** `blocklist.txt` and `portpilot blocklist`
   annotate observations only. Do not label the UI action as network blocking.
   Domain matching does not resolve domains to IPs; CIDR matching here is IPv4-only,
   with exact IPv6 addresses supported. Existing matcher caches last 60 seconds.
5. **Explicit network exposure:** app Quick Proxy defaults to IPv4 loopback.
   Opt-in source CIDRs are not authentication or encryption and do not restrict
   the listener to one LAN interface. Keep target-service auth/TLS; recommend
   narrow /32 or /128 client entries, never all-address /0 ranges or router
   forwarding. Retain admission caps, idle deadlines, port validation, and
   idempotent cleanup. CLI `proxy` uses OpenSSH SOCKS and has different controls.
6. **Deliberate effects:** kill/freeze/resume, Guard, cron edits/runs/stops, Docker
   control, and proxy listeners/outbound connections change real state. Recheck
   current process identity before destructive actions; PIDs can be stale/reused.
   Do not claim an async effect completed before its result is known. Reserved
   ports warn; they do not prevent kills. Guard can terminate later holders even
   when threat monitoring is paused; it is not guaranteed firewall enforcement.
7. **Cron is code execution:** Run Now deliberately invokes `/bin/sh -c` with
   user authority, without a sandbox. Preserve bounded output (256 KiB), the
   manual-run deadline (one hour), private temporary crontabs, and cleanup.
   Stopping descendants is best-effort, not guaranteed cancellation of detached
   work. Independently scheduled OS cron runs are outside that manual-run cap.
8. **Private, bounded storage:** sensitive POSIX files use 0600 and app-owned
   directories 0700. Temporary content must be protected before write by 0600
   files or a private 0700 containing directory. Do not
   chmod arbitrary caller-owned parents. Keep atomic replacement and history/output
   limits. Permissions are not encryption or Windows ACL enforcement. Cron commands
   and captured output may contain secrets; never log or commit tokens, account
   files, Keychain material, or real private history. Redact shared diagnostics.
9. **Incarnation and receipt safety:** cached process actions require the captured
   start identity and a fresh match before every signal/escalation. Missing or
   changed identity refuses the effect; EPERM is not evidence of exit. PID 0/1
   are invalid targets. Only confirmed termination receipts justify “stopped”.
   Guard must not arm from failed discovery, and lifecycle tokens are per port.
   Disarm synchronously invalidates enforcement generations, including pending
   escalation; re-enable must not revive old attempts. Delivered signals cannot
   be undone, and the final validation-to-signal race remains.
   User-space validation is not an atomic kernel process handle.
10. **Transactional configuration:** cron edits require complete checked reads,
    exact duplicate selection, a shared edit lock and a conflict reread. Independent
    editors can still race after the comparison; never claim crontab CAS. Alert-list
    read/modify/write requires a shared cross-process lock plus atomic replacement.
11. **Truthful delivery and startup:** release wrappers must preserve failed exit
    status. Login-item UI reports observed macOS registration, approval and errors,
    not merely the requested preference. Do not launch a test app automatically:
    restored Guard settings can have real effects.
12. **Signed, audited delivery:** releases require a verified Developer ID identity,
    never unsigned or ad-hoc signing. Commits and annotated tags must be signed
    and verified; never fall back to unsigned when signing fails. Finish the audit,
    then branch → PR → main; tag only the audited main revision. Do not push
    directly to main, make lightweight tags, or rewrite existing signed history.
    A signed local test build is not a notarized release. Notarization requires
    separate service authorization. Retain old artifacts until the replacement
    is verified; remove only exact in-scope targets, never broad cleanup.

## Where changes belong

- Detection and learning: `Sources/PortManagerLib/ThreatDetector.swift`,
  `ThreatModels.swift`, `PortManager+Connections.swift`.
- Polling, degraded state, and alert cooldowns:
  `Sources/PortPilot/Stores/ThreatMonitorStore.swift`.
- Listener policy: `Sources/PortManagerLib/TCPProxyManager.swift`;
  app opt-in controls: `Sources/PortPilot/ConfigurationPanel.swift`.
- Persistence and command boundaries: `SecuritySupport.swift`, `BlocklistStore.swift`,
  `ThreatHistoryStore.swift`, `CronRunManager.swift`, `PortManager+CronControl.swift`,
  and the checked command runner in `PortManager.swift`.
- User guidance: `Sources/PortPilot/SecurityFAQView.swift` (Settings and Security
  Center), this file, `mission.md`, and `docs/THREAT_ENGINE.md`. Keep their claims
  aligned with implementation; state unsupported behavior instead of promising it.

## Verification

Use synthetic connections, temporary private directories, harmless disposable
processes, and loopback-only fixtures. Never kill a real service, rewrite the
operator's crontab, contact a remote endpoint, or enable Guard just to test a change.

With dependencies already cached locally:

```sh
swift test --disable-automatic-resolution --skip-update
swift build --product portpilot --disable-automatic-resolution --skip-update
xcodebuild -project PortPilot.xcodeproj -scheme PortPilot -configuration Debug -destination 'platform=macOS' -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build
plutil -lint PortPilot.xcodeproj/project.pbxproj
git -c core.whitespace=cr-at-eol diff --check
```

Resolution/update flags are not a network sandbox. Check caches first; if a tool
wants to fetch, stop and report the missing dependency. Xcode directly compiles
shared sources while SwiftPM imports `PortManagerLib`; maintain both build paths
and add new app files to the Xcode source phase. Report exactly which targets and
platforms passed, what was not exercised, and any remaining live-validation gate.

The three-agent follow-up and safe reproductions are recorded in
[docs/SECURITY_REVIEW_2026-10-22.md](docs/SECURITY_REVIEW_2026-10-22.md).
Test releases use a padded display version such as `3.05.0001`; the canonical
package/build version remains valid unpadded semver (`3.5.1`). Keep generated
apps/archives under ignored `build/`, and do not replace the installed copy.

Public releases go to three channels: GitHub Releases, npm, and the Homebrew
cask in `sriinnu/homebrew-tap`. CI publishes none of them. The operator's
step-by-step runbook is private (`docs/harness/RELEASING.md`, a local link that
is never committed); notarization stays operator-run, and CI only stages npm
versions (`npm-publish.yml`), which the operator approves, with an
interactive login and security-key 2FA each time.
