#!/bin/bash
# Build PortPilot (Release) and install it into /Applications.
#
# Usage: scripts/dev-install.sh [--clean]
#   --clean  also wipes .build and Xcode DerivedData first (full rebuild)
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--clean" ]]; then
    echo "==> Wiping build artifacts"
    rm -rf .build
    rm -rf ~/Library/Developer/Xcode/DerivedData/PortPilot-*
fi

echo "==> Generating project"
xcodegen generate

echo "==> Building Release"
LOG=$(mktemp /tmp/portpilot-build.XXXXXX)
if ! xcodebuild -project PortPilot.xcodeproj -target PortPilot \
        -configuration Release SYMROOT=.build/xcode build >"$LOG" 2>&1; then
    grep -E "error: " "$LOG" | head -20
    echo "error: build failed — full log: $LOG" >&2
    exit 1
fi
echo "    $(grep -cE 'warning: ' "$LOG" || true) warnings"
rm -f "$LOG"

APP=".build/xcode/Release/PortPilot.app"
if [[ ! -d "$APP" ]]; then
    echo "error: build product missing: $APP" >&2
    exit 1
fi

# Quit a running copy so the bundle swap can't half-apply.
if pgrep -x PortPilot >/dev/null 2>&1; then
    echo "==> Quitting running PortPilot"
    osascript -e 'tell application "PortPilot" to quit' 2>/dev/null || pkill -x PortPilot || true
    sleep 1
fi

echo "==> Installing to /Applications"
rm -rf /Applications/PortPilot.app
cp -R "$APP" /Applications/PortPilot.app

VERSION=$(defaults read /Applications/PortPilot.app/Contents/Info.plist CFBundleShortVersionString)
echo "==> Done — PortPilot $VERSION in /Applications"
