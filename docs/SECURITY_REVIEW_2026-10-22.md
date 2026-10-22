# Three-agent security follow-up — 2026-10-22

This supplements [the trust-boundary assessment](../ports-threat-model.md).
Evidence is from the current source and local synthetic regressions, not scanner
output. These are local-user utility boundaries, not a new remote-admin service.
The user approved remediation. Installed/live and Windows acceptance remain
separate gates. No real crontab, user job, or production service is a test target.

## SR-01 — Guard can arm from failed discovery; unrelated disable cancels setup

- Exact path: `Sources/PortPilot/Stores/PortGuardStore.swift`,
  `snapshotGrandfathers`, `disable`, and sweep lifecycle; shared policy in
  `Sources/PortManagerLib/PortGuardPolicy.swift`.
- Prerequisites: an operator enables/restores Guard while discovery fails, or
  disables one port while another port's baseline is pending. A local process can
  also acquire a guarded port after a grandfathered process exits.
- Reachable path: `try?` failure was converted to `[]`, then accepted as the
  grandfather baseline. A later successful poll could terminate the original
  legitimate holder. A single global generation could discard unrelated setup.
  PID-only grandfathering could spare a different process after PID reuse.
  Disarm was also queued behind synchronous termination, allowing an in-flight
  TERM attempt to escalate after the UI already reported disarmed.
- Impact: unintended termination, silently inactive guards, or missed eviction.
- Confidence: high from source. Exploit timing depends on OS discovery failure
  or process lifecycle; no remote attacker or privilege escalation is assumed.
- Smallest correct fix: per-port lifecycle tokens, only successful complete
  snapshots arm Guard, incarnation-bound grandfathering/actions, truthful receipts,
  and a synchronously invalidated enforcement generation checked before signals
  and escalation. Already delivered signals cannot be undone.
- Safe regression: injected discovery failure then recovery must emit no kill;
  disabling B must not cancel A; a reused PID must not inherit grandfathering.
  Disarm during a fake TERM wait must cancel escalation, even after re-enable.

## SR-02 — Incomplete/stale crontab replacement and wrong duplicate selection

- Exact path: `Sources/PortManagerLib/PortManager+CronControl.swift`,
  `setCronjobPaused` and `writeCrontab`; duplicate identity originates in
  `PortManager+CronDiscovery.swift`.
- Prerequisites: an operator pauses/resumes a job during a failed/truncated read
  or concurrent edit, or chooses the second occurrence of a duplicate job.
- Reachable path: unchecked quiet output became the replacement crontab;
  matching stopped at the first schedule/command and ignored `duplicateIndex`.
- Impact: loss of unrelated scheduled jobs, overwritten edits, wrong job toggled.
- Confidence: high. The original runner has explicit partial/timeout states;
  this is not a claim that every normal read fails.
- Smallest correct fix: checked complete reads, exact occurrence transformation,
  serialized PortPilot transactions, and compare-before-install refusal on drift.
- Safe regression: injected partial/nonzero/timeout reads and conflicting reread
  must never call the installer; only the selected duplicate changes.
- Residual: system `crontab` has no compare-and-swap API. An independent editor
  can still race between the final comparison and installation; inspect changes.

## SR-03 — Cached PID actions can signal another incarnation

- Exact paths: `Sources/PortPilot/SecurityCenterView.swift` finding actions;
  `Sources/PortPilot/PortViewModel.swift` kill/freeze/resume paths;
  `Sources/PortManagerLib/PortManager.swift` signaling and escalation;
  `Sources/PortPilot/MenuBarController.swift` notification kill action.
  CLI/TUI cached paths also include `Sources/PortKillerCLI/InteractiveMode.swift`
  (`promptKillSelected`/`handleKillConfirmation`),
  `Sources/PortPilotTUI/ConnectionDetailScreen.swift` and `PortDetailScreen.swift`
  (`killProcess`), and `Sources/PortPilotTUI/PortListScreen.swift` (`killSelected`).
- Prerequisites: a displayed/queued action outlives its process and the OS reuses
  the PID, or a notification's port is acquired by another process.
- Reachable path: stale observation supplied only a PID/port to a fresh effect.
- Impact: termination or suspension of an unrelated same-authority process.
- Confidence: high for the reachable identity gap; practical PID reuse timing
  varies. The attacker does not gain authority beyond the current OS user.
- Smallest correct fix: bind observation to process-start identity, revalidate
  immediately before signals and escalation, refuse unavailable/stale identities,
  and remove destructive actions from stale port-only notifications.
- Safe regression: swap the fake process incarnation before TERM, STOP, or KILL;
  assert zero signals to the replacement and an explicit unresolved result.
- Residual: user-space check-then-signal is not an atomic kernel process handle.

## SR-04 — Signal failures are reported as successful stops

- Exact paths: `Sources/PortManagerLib/PortManager.swift`, `killProcess`,
  `killProcessByPID`; `Sources/PortManagerLib/CronRunManager.swift`, `stop`;
  `Sources/PortPilot/Stores/CronjobController.swift`, `stop`; Guard eviction log.
- Prerequisites: an operator requests an invalid/protected PID or a process
  survives/refuses a signal. This is an outcome-integrity defect, not remote RCE.
- Reachable path: ignored signal errno, `kill(pid, 0)` EPERM treated as absence,
  PID 1 filtered to an empty survivor list, and Stop returning tracked-exists.
- Impact: misleading success while work remains active or was never signaled.
- Confidence: high from the OS return-value handling and caller paths.
- Smallest correct fix: structured per-target receipts; EPERM means present but
  inaccessible; invalid, stale, unknown, and surviving targets remain unresolved.
- Safe regression: fake EPERM, PID 1, missing identity, and surviving processes;
  no fixture sends signals to protected or real user processes.

## SR-05 — Release wrappers hide failures

- Exact path: `package.json`, `build`, `build:all`, `install:cli`, `install:tui`,
  and the `release` chain.
- Prerequisites: a build/copy command fails. No attacker is necessary; a local
  build-tool or filesystem failure is enough.
- Reachable path: `xcodebuild | tail`, semicolon sequencing, and successful
  fallback echoes converted failure to exit status zero.
- Impact: false delivery success, stale/missing test or installed artifacts.
- Confidence: high; reproduced with harmless failing command stubs.
- Smallest correct fix: preserve pipeline exit status and stop dependent steps
  after failure; fallback advice must return nonzero.
- Safe regression: mocked build/npm/copy failures; no installation or fetch.

## SR-06 — Concurrent alert-list updates lose accepted rules

- Exact path: `Sources/PortManagerLib/BlocklistStore.swift`, `add`/`remove`.
- Prerequisites: two app/CLI store instances update the same list concurrently.
- Reachable path: independent instance locks protected separate read-modify-write
  transactions; atomic rename prevented partial files, not lost updates.
- Impact: an accepted detection rule can disappear. This list never enforces
  packet blocking, so the impact is lost detection configuration, not firewall bypass.
- Confidence: high. Requires concurrent writers with access to the same list.
- Smallest correct fix: a private shared sidecar transaction lock covering the
  full read-transform-atomic-write cycle, including separate processes.
- Safe regression: two stores write distinct rules to a temporary private path;
  both must survive and permissions remain private.

## SR-07 — Executable promotion trusts a one-off destination

- Exact path: `Sources/PortManagerLib/ThreatModels.swift`,
  `ThreatBaseline.advanceSnapshot` identity-promotion branch.
- Prerequisites: an observed executable recurs while changing remote endpoint.
- Reachable path: on identity promotion, all current remotes were unioned into
  the known set without their own recurrence history.
- Impact: reduced baseline-relative alerting for a one-off destination;
  absolute alert-list/count/fan-out rules still apply.
- Confidence: high; deterministic pure-model reproduction.
- Smallest correct fix: count remote candidates independently from the first
  snapshot; identity recurrence must not grant destination recurrence.
- Safe regression: snapshots `I+A`, then `I+B` promote I but neither A nor B;
  a third `I+B` can promote B. Interrupted candidates must start over.

## SR-08 — Monitoring chrome and notification destination misrepresent state

- Exact paths: `Sources/PortPilot/Liquid/MainStatusBar.swift`,
  `LiquidSidebar.swift`; `Sources/PortPilot/Stores/ThreatMonitorStore.swift`,
  `sendThreatNotification`; `MenuBarController.swift` response dispatch.
- Prerequisites: monitoring is paused/pending/degraded, or a user opens a threat
  notification. No malicious input is needed.
- Reachable path: fixed green live/nominal labels ignored monitor state and
  claimed a two-second sample; the advertised review action had no destination.
- Impact: false assurance and delayed access to findings.
- Confidence: high from the fixed labels and missing response branch.
- Smallest correct fix: common freshness presentation with real cadence and
  last-success state; explicit main-thread Security Center navigation.
- Safe regression: pure state and notification-route fixtures, without sending
  real notifications or launching the operational app.

## SR-09 — Launch-at-login preference reports intent as OS success

- Exact path: `Sources/PortPilot/AppSettings.swift`, `launchAtLogin` and
  registration task; `Sources/PortPilot/SettingsView.swift` toggle.
- Prerequisites: registration fails or needs macOS approval.
- Reachable path: preference persisted immediately; async errors were only
  logged, leaving the toggle presented as enabled.
- Impact: the app may not start and monitor after login despite the displayed
  preference. This is security-relevant availability/UX, not privilege escalation.
- Confidence: high; depends on ServiceManagement outcome.
- Smallest correct fix: publish observed OS state, pending approval and failure;
  reconcile after operations/activation and prevent concurrent preference races.
- Safe regression: fake registration states/errors; never change real login items.

## SR-10 — Discovery rows can inherit a replacement PID's identity

- Exact paths: `Sources/PortManagerLib/PortManager.swift`, listening discovery
  and `fetchFullCommandsMacOS`; `PortManager+Connections.swift`, connection
  discovery/enrichment; named-process discovery; Guard baseline capture in
  `Sources/PortPilot/Stores/PortGuardStore.swift`.
- Prerequisites: local process exit/PID reuse between a raw socket/name snapshot
  and later identity enrichment. Natural race frequency is low; no remote input
  alone establishes this prerequisite.
- Reachable path: raw discovery reports PID P's socket; P exits; enrichment
  obtains the replacement P's valid identity. A cached action can then validate
  and signal that replacement even though it never owned the observed socket.
- Impact: wrong same-user process control/termination. An unconfirmed empty
  Guard snapshot can also grandfather nobody and later evict a preexisting holder.
- Confidence: high from the separate discovery/enrichment code paths; injected
  tests establish refusal behavior, not a real PID-exhaustion exploit.
- Smallest remediation: repeat raw discovery after identity capture and bind
  actionable identities only to matching raw-row multisets. Missing/changed rows
  stay displayable but unbound. Guard requires identical holder multisets and
  identities for every holder; only two complete empty snapshots establish a
  free port. Second-read failures propagate, never become an empty success.
- Safe regression: pure fake listening/endpoint/name snapshots with PID reuse,
  changed endpoints, duplicate rows, appearing holders, and missing identities;
  assert no actionable token or armed Guard baseline. No OS signal is sent.
- Residual: validation is still user-space, not an atomic kernel signal handle.

## SR-11 — Failed alert-list reads can cause destructive replacement

- Exact path: `Sources/PortManagerLib/BlocklistStore.swift`, `add`/`remove` →
  `allLinesUnlocked` → atomic `writeUnlocked`.
- Prerequisites: an existing file is unreadable or invalid UTF-8 when a legitimate
  edit occurs. An attacker able to write this same-account file already has
  direct rule-editing power; this is data-integrity hardening, not escalation.
- Reachable path: a failed read used to return `[]`; Add treated that as an empty
  list and replaced the existing bytes with only the new entry.
- Impact: loss of previously configured alert rules/comments. This list performs
  detection classification, not packet filtering.
- Confidence: high; a private invalid-UTF-8 fixture reproduces the failure mode.
- Smallest remediation: transactional mutations throw for failed existing-file
  reads; only an exact missing-file error is a valid empty state. Correct the
  formatting claim: comments remain, but whitespace/blanks are normalized.
- Safe regression: `CronPersistenceConcurrencyTests.testBlocklistMutationRefusesInvalidExistingFileWithoutOverwrite`
  asserts Add throws and the original fixture bytes are unchanged.
- Residual: the nonmutating `entries()` compatibility API still returns an empty
  list on read error. This fix does not make that API an error-reporting channel.

## Signed-delivery policy gap

The previous tag-triggered workflows could publish unsigned/ad-hoc artifacts;
the direct release scripts could commit/push/tag main or install automatically.
Those behaviors do not meet the operator's signed branch → PR → main policy.
They are delivery-policy gaps, not evidence of an unauthenticated remote exploit.
The replacement helpers require a clean main revision, verified commit, matching
signed annotated tag, matching app version and Developer ID signatures from the
configured team. Automatic GitHub/npm publication is disabled pending a trusted
signing workflow. Local checks cannot prove remote PR approval; delivery must
also verify the actual repository PR/main path.

## Verification record

Safe local regressions (all paths are under `Tests/PortPilotTests` unless noted):

| Finding | Executable evidence |
| --- | --- |
| SR-01 | `PortGuardPolicyTests.testFailedSnapshotDoesNotArmAndSuccessfulRetryGrandfathersHolder`, `testDisablingOnePortDoesNotInvalidateAnotherPendingSnapshot`, `testDisarmImmediatelyRevokesAttemptWithoutWaitingForQueuedCleanup`, `testRearmingDoesNotReviveThePreviousTerminationAttempt`, `testEnforcementGateKeepsPortsIndependent`, and PID-reuse/enrichment tests |
| SR-02 | `CronPersistenceConcurrencyTests.testIncompleteCrontabReadsAbortTransactionWithoutInstall`, `testChangedCrontabAbortsWithoutInstall`, and exact-duplicate/serialized-edit tests |
| SR-03 | `ProcessSafetyTests.testStaleIdentityFailsClosedWithoutSignal`, `testIdentityIsRecheckedBeforeKillEscalation`, `testCancellationAfterTermPreventsKillEscalation`, and tracked/independent cron identity regressions |
| SR-04 | `ProcessSafetyTests.testPermissionDeniedProbeMeansAliveAndNeverReportsSuccess`, `testProtectedAndInvalidPIDsAreRejectedWithoutSyscalls`, and cron stop-summary tests |
| SR-05 | `node scripts/release_scripts.test.cjs` — failing build/copy/generator stubs; no installation |
| SR-06 | `CronPersistenceConcurrencyTests.testConcurrentBlocklistStoresDoNotLoseUpdates` — two instances, private temporary list; cross-process serialization uses POSIX `flock` |
| SR-07 | `ThreatDetectorTests.testIdentityPromotionDoesNotTrustOneOffRemotes`, `testInterruptedRemoteCandidateMustRecurAgain` |
| SR-08 | `ProductPresentationTests` freshness/cadence and threat/legacy notification-routing cases |
| SR-09 | `ProductPresentationTests` fake login registration/removal/approval cases |
| SR-10 | `ProcessSafetyTests.testListeningIdentityRequiresSameSocketRowInConfirmationSnapshot`, `testConnectionIdentityRequiresSameEndpointRowInConfirmationSnapshot`, `testNamedProcessIdentityRequiresSameNamedRowInConfirmationSnapshot` |
| SR-11 | `CronPersistenceConcurrencyTests.testBlocklistMutationRefusesInvalidExistingFileWithoutOverwrite` |

The shared Swift suite passes **166 tests**; the mocked release-script suite
passes **33 tests**. The cached SwiftPM TUI build passes. Three permanent
`ProxyIntegrationTests` exercise an owned echo target and clients bound only to
`127.0.0.1`: forwarding, denied-peer/no-outbound, cap/idle cleanup and restart.
The read-only current-XCTest-process identity check also passes; it sends no
signals. Identity/control-outcome and crontab-transaction regressions use injected
fakes, not the operator's processes or crontab. A separate bounded manual-run
integration fixture starts its own disposable `sleep 30` command in temporary
storage and tests deadline termination; it does not run or edit an OS cron entry.
These are bounded-snapshot receipts, not proof that no detached/new descendants
exist.

macOS test artifact: display version `3.05.0001`, canonical package/build version
`3.5.1`. Build/signature validation is recorded with the packaged artifact. Do
not infer installed acceptance or Windows parity from these fixtures. Keep
Daybreak Blue and other existing protections enabled while testing.
