#!/usr/bin/env bash
set -euo pipefail

# I build, sign, notarize, and package a public macOS release from local credentials.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_ENV_FILE="$ROOT_DIR/.port.local.env"
BUILD_ROOT="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist/release"
APP_PATH="$BUILD_ROOT/Release/PortPilot.app"
ZIP_PATH="$DIST_DIR/PortPilot-macOS-app.zip"
CHECKSUM_PATH="$DIST_DIR/SHA256SUMS.txt"

if [[ -f "$LOCAL_ENV_FILE" ]]; then
  # I source only local release secrets from the ignored env file.
  # shellcheck disable=SC1090
  source "$LOCAL_ENV_FILE"
fi

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required environment variable: $name" >&2
    exit 1
  fi
}

require_env "APP_IDENTITY"
require_env "APP_STORE_CONNECT_KEY_ID"
require_env "APP_STORE_CONNECT_ISSUER_ID"
require_env "APP_STORE_CONNECT_API_KEY_P8"

mkdir -p "$DIST_DIR"
rm -rf "$APP_PATH" "$ZIP_PATH"

echo "Building PortPilot.app in Release mode..."
xcodebuild \
  -project "$ROOT_DIR/PortPilot.xcodeproj" \
  -target PortPilot \
  -configuration Release \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle not found at $APP_PATH" >&2
  exit 1
fi

echo "Signing PortPilot.app with Developer ID..."
codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp \
  --sign "$APP_IDENTITY" \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
API_KEY_FILE="$TEMP_DIR/AuthKey.p8"

# I materialize the API key from the local env value only for the notarization call.
printf '%s' "$APP_STORE_CONNECT_API_KEY_P8" > "$API_KEY_FILE"

echo "Creating notarization archive..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Submitting app for notarization..."
xcrun notarytool submit "$ZIP_PATH" \
  --key "$API_KEY_FILE" \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "Repacking stapled app..."
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$ZIP_PATH")" > "$(basename "$CHECKSUM_PATH")"
)

echo "Signed release ready:"
echo "  $ZIP_PATH"
echo "  $CHECKSUM_PATH"

# Push to Applications (set SKIP_APPLICATIONS=y to skip)
if [[ "${SKIP_APPLICATIONS:-n}" != "y" ]]; then
  if [[ -d "/Applications/PortPilot.app" ]]; then
    echo "Removing existing /Applications/PortPilot.app..."
    rm -rf "/Applications/PortPilot.app"
  fi
  echo "Installing PortPilot.app to /Applications..."
  cp -R "$APP_PATH" "/Applications/PortPilot.app"
  # Clear quarantine attribute to avoid Gatekeeper issues with copied apps
  xattr -cr "/Applications/PortPilot.app"
  echo "Installed to /Applications/PortPilot.app"
else
  echo ""
  echo "Skipped /Applications installation (SKIP_APPLICATIONS=y)"
fi
