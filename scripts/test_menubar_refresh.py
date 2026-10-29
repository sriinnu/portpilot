#!/usr/bin/env python3
"""Build/run the native refresh regression with a fresh home; no installed app.

Uses only the SDK and repository sources. No packages, network, signing, login
registration, notifications, crontab, Guard, or real app preferences are used.
The test opens a temporary native popover and loopback-only TCP listeners.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / "menubar-regression"
OUT.mkdir(parents=True, exist_ok=True)
controller = ROOT / "Sources/PortPilot/MenuBarController.swift"
entry = ROOT / "Sources/PortPilot/PortPilotApp.swift"
fixture = ROOT / "Scripts/MenuBarRefreshRegression.swift"
# Keep private test probes in a generated compilation unit, never the app.
combined = OUT / "MenuBarController+Regression.swift"
combined.write_text(controller.read_text() + "\n" + fixture.read_text())
delegate = OUT / "AppDelegate.swift"
app_source = entry.read_text()
delegate.write_text("import SwiftUI\nimport AppKit\n" + app_source[app_source.index("@MainActor\nclass AppDelegate"):] + '''
extension AppDelegate {
    var regressionAutoRefreshInterval: TimeInterval? { autoRefreshTimer?.timeInterval }
    func regressionObserveRefreshSettings() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleAutoRefreshChanged),
                                              name: .autoRefreshChanged, object: nil)
        setupAutoRefreshTimer()
    }
    func regressionStopRefreshObservation() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
        NotificationCenter.default.removeObserver(self, name: .autoRefreshChanged, object: nil)
    }
}
''')
sources = sorted(str(p) for directory in ("Sources/PortPilot", "Sources/PortManagerLib")
                 for p in (ROOT / directory).rglob("*.swift") if p not in (controller, entry))
binary = OUT / "PortPilotMenuBarRegression"
with (OUT / "compile.log").open("w") as log:
    result = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5",
                             "-whole-module-optimization",
                             "-module-name", "PortPilotMenuBarRegression", *sources,
                             str(combined), str(delegate), "-o", str(binary)], cwd=ROOT,
                            stdout=log, stderr=subprocess.STDOUT)
if result.returncode:
    print(f"Native compilation failed: {OUT / 'compile.log'}", flush=True)
    raise SystemExit(result.returncode)
print("Native compilation passed", flush=True)
for arguments, extra_rule in (
    ([], ''),
    (["--deny-discovery"], '(deny process-exec (literal "/usr/sbin/lsof"))'),
):
    with tempfile.TemporaryDirectory(prefix="portpilot-menubar-regression-") as isolated:
        env = dict(os.environ, HOME=isolated, CFFIXED_USER_HOME=isolated,
                   PORTPILOT_REGRESSION_HOME=isolated)
        # Child discovery commands inherit the restriction; fixtures only listen.
        profile = '(version 1)(allow default)(deny network-outbound (remote ip "*:*"))' + extra_rule
        result = subprocess.run(["sandbox-exec", "-p", profile, str(binary), *arguments],
                                env=env, cwd=isolated, timeout=240)
        if result.returncode:
            raise SystemExit(result.returncode)
