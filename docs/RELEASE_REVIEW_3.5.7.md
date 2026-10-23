# PortPilot 3.5.7 release review

Two independent source reviews covered the cumulative core/security changes,
packet capture lifecycle, native UI, process controls, Xcode source coverage,
and release scripts. No scanner output was treated as a confirmed vulnerability.

Corrections from review:

- Packet capture now records late child exit monotonically and retains the child
  until settlement. An unconfirmed stop cannot permanently block retry or Quit
  after the child has actually exited. A disposable sleep child with unavailable
  signal identity covers this regression without capture-device access.
- A completed old capture model can clear the global slot only if it still owns
  that slot; it cannot erase a newer capture's ownership.
- Checked subprocess output requires confirmed pipe EOF. A delayed inherited
  writer is reported as incomplete and cannot pass checked crontab parsing.

The reviewers found no further source release blockers after these corrections.
Local validation uses synthetic fixtures only. Actual packet capture, restored
Guard behavior, native sheet/key-window acceptance, login startup, and Windows
parity are separate live acceptance gates. Linux requires its GitHub CI result.
Release artifacts must be rebuilt from the merged audited main revision and
verified with Developer ID signatures; tags and commits require verified
signatures. This review does not establish notarization or live device safety.
