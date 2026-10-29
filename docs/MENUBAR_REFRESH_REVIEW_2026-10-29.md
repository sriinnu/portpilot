# Menu-bar refresh review — 2026-10-29

Scope: the reported badge that changed only after opening the popover.
This is a correctness review and local native regression, not the pending
Daybreak security audit or acceptance of an installed release.

## Confirmed paths and changes

- `Sources/PortPilot/MenuBarController.swift`, `startMetricsUpdates` previously
  redrew cached metrics; discovery ran in a timer owned by the open panel.
  With app-wide Auto-refresh off, a closed panel never refreshed discovery.
  `startPortRefreshes` now belongs to the controller lifetime, observes interval
  changes, and runs in common run-loop modes. Dismissing the panel retains it;
  controller teardown invalidates it. App-wide Auto-refresh takes precedence.
- `MenuBarController.init` now receives model changes on the next main run-loop
  turn. AppKit reads the committed snapshot/timeline rather than pre-mutation
  `objectWillChange` state. Opening the panel clears the glance badge immediately.
- `Sources/PortPilot/PortPilotApp.swift`, `setupAutoRefreshTimer` could supersede
  an unfinished scan every tick. Both timer paths now call
  `PortViewModel.refreshInBackground`, which checks port and connection work
  independently. Manual refresh retains latest-request-wins behavior.
- `Sources/PortPilot/PortViewModel.swift`, `refreshPorts` previously compared the
  next full scan with the last displayed range-limited cache. Clearing a range
  could falsely emit new binds for ports outside that range. Only full successful
  scans now update `timelinePortsCache`; ranged and failed scans do not.
- The native tooltip explains that the badge counts **bound/released events
  since the last glance**, not total open ports. It distinguishes pending/failed
  initial discovery from a successful empty snapshot and timestamps the last
  successful snapshot. The existing settings footer now describes background
  menu-bar polling and app-wide interval precedence.
- Connection alerts check the global notification preference before touching
  the notification singleton. An unbundled executable cannot register with
  UserNotifications, avoiding its Objective-C exception in the native test host.

## Performed verification

```sh
python3 scripts/test_menubar_refresh.py
swift test --disable-automatic-resolution --skip-update
plutil -lint PortPilot.xcodeproj/project.pbxproj
git -c core.whitespace=cr-at-eol diff --check
```

- Native compilation and linking passed using repository app/shared sources and
  the local SDK. The test entry point replaces the app launcher; production
  controller, view model, discovery, panel, and app-wide timer code are retained.
- **48 native checks passed:** real ephemeral IPv4 loopback listeners appear and
  disappear in the production scanner while the popover stays closed; native
  button titles update; post-mutation delivery, immediate reset, live interval
  changes, interval clamping, app-wide timer discovery and handoff, busy scans,
  invalid-range failure retention, range/full-scan transitions, actual AppKit
  panel visibility, open/close polling, connection-policy failure degradation,
  last-good retention, menubar truthfulness, threat-freshness precedence,
  stale-metric suppression and recovery, deallocation, and timer cleanup work.
- **6 native fault checks passed** in a second fresh process with the OS sandbox
  denying execution of `/usr/sbin/lsof`: failure is reported, no successful
  refresh or lifecycle event is claimed, and the tooltip reports unavailable
  discovery. Guard and threat polling remain off in both processes.
- **192 SwiftPM tests passed**, zero failures. Project plist, Python driver
  syntax, and whitespace checks passed. Existing compiler warnings remain.

The native driver uses a verified temporary home and explicit empty Guard
settings, omits threat polling and notification registration, and blocks outbound
IP networking for both the runner and discovery children. It does not invoke
cron, destructive process actions, Docker, SSH, login registration, credential
stores, or the installed app. Private probes exist only in generated test source
under ignored `build/menubar-regression/`; compile output is `compile.log` there.
Store/VM initialization defaults retain normal app startup behavior.

## Limits and audit handoff

The installed `/Applications/PortPilot.app` was neither replaced nor launched.
This does not validate its current binary, signed bundle packaging, normal
persisted-state startup, notification delivery, login items, sleep/wake behavior,
or Windows. Polling can miss listeners that start and stop between snapshots;
the badge is not a complete OS event stream. Manual overlapping refreshes still
use the existing latest-request-wins behavior.

Changes remain uncommitted for review. The broader security audit, signed app
delivery, and installed-app acceptance are separate remaining gates.
