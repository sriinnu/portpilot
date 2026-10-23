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
  writer that has not reached EOF is reported as incomplete and cannot pass
  checked crontab parsing. Foundation may defer process termination delivery
  until that writer drains on Linux; complete output with confirmed EOF remains
  valid. The regression checks both valid platform outcomes.
- Linux CI exposed failing Foundation replacement of existing private files.
  Darwin/Linux now use atomic sibling POSIX rename, retaining the temporary
  file's 0600 permissions. Existing blocklist round-trip and concurrent-writer
  tests cover replacement and lost updates.
- Packet capture and the checked command runner confirm pipe EOF through nonblocking reads, rather than
  relying on Foundation's readability callback to report EOF for short-lived
  Linux children. Reads remain bounded and missing EOF remains incomplete.
- Linux process incarnation reads explicitly consume procfs data to EOF,
  independent of its reported zero file size. Fresh before/after incarnation
  comparisons and fail-closed signal authorization remain unchanged.

The reviewers found no further source release blockers after these corrections.
Local validation uses synthetic fixtures only. Actual packet capture, restored
Guard behavior, native sheet/key-window acceptance, login startup, and Windows
parity are separate live acceptance gates. Linux requires its GitHub CI result.
Release artifacts must be rebuilt from the merged audited main revision and
verified with Developer ID signatures; tags and commits require verified
signatures. This review does not establish notarization or live device safety.
