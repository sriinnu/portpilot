#!/usr/bin/env bash
set -euo pipefail

# I generate a PortPilot-specific Sparkle Ed25519 key using Sparkle's official tool.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_ENV_FILE="$ROOT_DIR/.port.local.env"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-portpilot}"
SPARKLE_PRIVATE_KEY_FILE="${SPARKLE_PRIVATE_KEY_FILE:-$HOME/.config/portpilot/sparkle_private_key}"

if [[ -f "$LOCAL_ENV_FILE" ]]; then
  # I only source local machine overrides from the ignored env file.
  # shellcheck disable=SC1090
  source "$LOCAL_ENV_FILE"
fi

resolve_generate_keys_bin() {
  local candidate=""

  if [[ -n "${SPARKLE_GENERATE_KEYS_BIN:-}" && -x "${SPARKLE_GENERATE_KEYS_BIN:-}" ]]; then
    printf '%s\n' "$SPARKLE_GENERATE_KEYS_BIN"
    return 0
  fi

  if command -v generate_keys >/dev/null 2>&1; then
    command -v generate_keys
    return 0
  fi

  shopt -s nullglob
  for candidate in \
    "$HOME"/Library/Developer/Xcode/DerivedData/*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys \
    "$HOME"/Library/Developer/Xcode/DerivedData/*/SourcePackages/checkouts/Sparkle/generate_keys \
    /opt/homebrew/bin/generate_keys \
    /usr/local/bin/generate_keys
  do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  shopt -u nullglob

  return 1
}

GENERATE_KEYS_BIN="$(resolve_generate_keys_bin || true)"
if [[ -z "$GENERATE_KEYS_BIN" ]]; then
  echo "Unable to find Sparkle's generate_keys tool." >&2
  echo "Set SPARKLE_GENERATE_KEYS_BIN to the full path and re-run this script." >&2
  exit 1
fi

mkdir -p "$(dirname "$SPARKLE_PRIVATE_KEY_FILE")"

if [[ -f "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
  backup_path="${SPARKLE_PRIVATE_KEY_FILE}.bak-$(date +%Y%m%d-%H%M%S)"
  cp "$SPARKLE_PRIVATE_KEY_FILE" "$backup_path"
  echo "Backed up existing exported key to $backup_path"
fi

echo "Generating or looking up Sparkle keychain key for account: $SPARKLE_KEY_ACCOUNT"
"$GENERATE_KEYS_BIN" --account "$SPARKLE_KEY_ACCOUNT" >/dev/null

echo "Exporting private key to: $SPARKLE_PRIVATE_KEY_FILE"
"$GENERATE_KEYS_BIN" --account "$SPARKLE_KEY_ACCOUNT" -x "$SPARKLE_PRIVATE_KEY_FILE"
chmod 600 "$SPARKLE_PRIVATE_KEY_FILE"

PUBLIC_KEY="$("$GENERATE_KEYS_BIN" --account "$SPARKLE_KEY_ACCOUNT" -p | tail -n 1 | tr -d '\r')"
if [[ -z "$PUBLIC_KEY" ]]; then
  echo "Failed to resolve Sparkle public key for account: $SPARKLE_KEY_ACCOUNT" >&2
  exit 1
fi

echo ""
echo "Sparkle key ready."
echo "  Account: $SPARKLE_KEY_ACCOUNT"
echo "  Private key: $SPARKLE_PRIVATE_KEY_FILE"
echo "  Public key: $PUBLIC_KEY"
echo ""
echo "If you embed Sparkle later, set SUPublicEDKey to the public key above."
