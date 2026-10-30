#!/usr/bin/env bash
set -euo pipefail

# Public policy only. Never load signing keys, local credential files, or services.
RELEASE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

release_fail() {
  echo "Release refused: $*" >&2
  exit 1
}

verify_release_source() {
  local package_version branch state commit tagged_commit tag_type
  package_version="$(node -p "require(process.argv[1]).version" "$RELEASE_ROOT/package.json")"
  RELEASE_VERSION="${1:-$package_version}"
  [[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || release_fail "use a three-part version, e.g. 3.5.1"
  [[ "$RELEASE_VERSION" == "$package_version" ]] || release_fail "version must already match package.json; submit version changes through a signed branch/PR"
  cd "$RELEASE_ROOT"
  branch="$(git symbolic-ref --quiet --short HEAD)" || release_fail "release handoff requires audited main, not a detached checkout"
  [[ "$branch" == main ]] || release_fail "release handoff requires audited main after branch/PR review"
  state="$(git status --porcelain --untracked-files=normal)" || release_fail "working-tree status is unavailable"
  [[ -z "$state" ]] || release_fail "working tree must be clean"
  git verify-commit HEAD || release_fail "HEAD must have a verifiable trusted signature"
  RELEASE_TAG="v$RELEASE_VERSION"
  tag_type="$(git cat-file -t "refs/tags/$RELEASE_TAG")" || release_fail "matching signed tag $RELEASE_TAG is missing"
  [[ "$tag_type" == tag ]] || release_fail "$RELEASE_TAG must be an annotated signed tag, not a lightweight tag"
  git verify-tag "$RELEASE_TAG" || release_fail "$RELEASE_TAG must have a verifiable trusted signature"
  commit="$(git rev-parse HEAD)"
  tagged_commit="$(git rev-parse "refs/tags/$RELEASE_TAG^{commit}")"
  [[ "$commit" == "$tagged_commit" ]] || release_fail "$RELEASE_TAG must point to HEAD"
  RELEASE_COMMIT="$commit"
}

verify_release_artifact() {
  local artifact="$1" requirement code_path executable_name architectures arch signature_metadata entitlements compact_entitlements exception
  [[ -e "$artifact" ]] || release_fail "artifact not found: $artifact"
  RELEASE_TEAM_ID="${PORTPILOT_RELEASE_TEAM_ID:-RSH5FK4MB6}"
  [[ "$RELEASE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || release_fail "PORTPILOT_RELEASE_TEAM_ID must be an explicit ten-character Apple team ID"
  # Apple anchoring + the Developer ID Application leaf extension rejects
  # unsigned, ad-hoc and Apple Development signatures, even from this team.
  requirement="=anchor apple generic and certificate leaf[subject.OU] = \"$RELEASE_TEAM_ID\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
  codesign --verify --all-architectures --deep --strict --test-requirement "$requirement" "$artifact" || release_fail "artifact requires an intact Developer ID Application signature from team $RELEASE_TEAM_ID: $artifact"

  code_path="$artifact"
  if [[ -d "$artifact" ]]; then
    executable_name="$(plutil -extract CFBundleExecutable raw -o - "$artifact/Contents/Info.plist")" || release_fail "app executable name is unavailable: $artifact"
    code_path="$artifact/Contents/MacOS/$executable_name"
    [[ -f "$code_path" ]] || release_fail "app executable is missing: $code_path"
  fi
  architectures="$(lipo -archs "$code_path")" || release_fail "artifact architectures are unavailable: $code_path"
  [[ -n "$architectures" ]] || release_fail "artifact has no reported architecture: $code_path"
  for arch in $architectures; do
    signature_metadata="$(codesign --display --verbose=4 --arch "$arch" "$code_path" 2>&1)" || release_fail "artifact signature metadata is unavailable for $arch: $code_path"
    grep -Eq 'flags=0x[[:xdigit:]]*\([^)]*runtime[^)]*\)' <<<"$signature_metadata" || release_fail "artifact must be signed with hardened runtime for $arch: $code_path"

    entitlements="$(codesign --display --entitlements :- --arch "$arch" "$code_path" 2>/dev/null)" || release_fail "artifact entitlements are unavailable for $arch: $code_path"
    compact_entitlements="$(tr -d '[:space:]' <<<"$entitlements")"
    for exception in \
      com.apple.security.get-task-allow \
      com.apple.security.cs.allow-jit \
      com.apple.security.cs.allow-unsigned-executable-memory \
      com.apple.security.cs.disable-executable-page-protection \
      com.apple.security.cs.disable-library-validation \
      com.apple.security.cs.debugger \
      com.apple.security.cs.allow-dyld-environment-variables; do
      [[ "$compact_entitlements" != *"<key>$exception</key><true/>"* ]] || release_fail "artifact enables forbidden hardened-runtime exception entitlement $exception for $arch: $code_path"
    done
  done
}

release_artifact_paths() {
  RELEASE_APP="${PORTPILOT_APP_PATH:-$RELEASE_ROOT/.build/xcode/Build/Products/Release/PortPilot.app}"
  RELEASE_CLI="${PORTPILOT_CLI_PATH:-$RELEASE_ROOT/.build/release/portpilot}"
  RELEASE_TUI="${PORTPILOT_TUI_PATH:-$RELEASE_ROOT/.build/release/portpilot-tui}"
}

verify_release_artifacts() {
  local mode="${1:-all}" app_version
  release_artifact_paths
  [[ -d "$RELEASE_APP" ]] || release_fail "app bundle not found: $RELEASE_APP"
  verify_release_artifact "$RELEASE_APP"
  app_version="$(plutil -extract CFBundleVersion raw -o - "$RELEASE_APP/Contents/Info.plist")" || release_fail "app bundle version is unavailable"
  [[ "$app_version" == "$RELEASE_VERSION" ]] || release_fail "app bundle version does not match signed release tag"
  if [[ "$mode" == all ]]; then
    [[ -f "$RELEASE_CLI" && -x "$RELEASE_CLI" ]] || release_fail "CLI executable not found: $RELEASE_CLI"
    [[ -f "$RELEASE_TUI" && -x "$RELEASE_TUI" ]] || release_fail "TUI executable not found: $RELEASE_TUI"
    verify_release_artifact "$RELEASE_CLI"
    verify_release_artifact "$RELEASE_TUI"
  fi
}

package_release_artifacts() {
  local mode="${1:-all}" release_dist
  release_dist="${PORTPILOT_RELEASE_DIR:-$RELEASE_ROOT/dist/release/$RELEASE_TAG}"
  mkdir -p "$release_dist"
  RELEASE_STAGE="$(mktemp -d "$release_dist/.stage.XXXXXX")"
  # Only this fresh, private staging directory is removed; never the output or app.
  trap 'rm -rf -- "$RELEASE_STAGE"' EXIT
  ditto -c -k --sequesterRsrc --keepParent "$RELEASE_APP" "$RELEASE_STAGE/PortPilot-macOS-app.zip"
  if [[ "$mode" == all ]]; then
    # Binaries unzip flat, without a build-dir parent or AppleDouble ._ files.
    ditto -c -k --norsrc --noextattr --noacl "$RELEASE_CLI" "$RELEASE_STAGE/portpilot-macos-cli.zip"
    ditto -c -k --norsrc --noextattr --noacl "$RELEASE_TUI" "$RELEASE_STAGE/portpilot-macos-tui.zip"
  fi
  printf 'Tag: %s\nCommit: %s\nDeveloper ID team: %s\nNotarization: not performed by this offline handoff\n' "$RELEASE_TAG" "$RELEASE_COMMIT" "$RELEASE_TEAM_ID" > "$RELEASE_STAGE/RELEASE.txt"
  (cd "$RELEASE_STAGE" && shasum -a 256 ./*.zip > SHA256SUMS.txt)
  mv "$RELEASE_STAGE"/* "$release_dist/"
  echo "Verified signed local handoff: $release_dist"
  echo "No publishing, installation, notarization, commit, or tag was performed."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  mode="${1:-all}"
  case "$mode" in
    source)
      verify_release_source "${2:-}"
      echo "Existing signed commit/tag verified; no commit or tag was created."
      ;;
    all)
      verify_release_source "${2:-}"
      verify_release_artifacts all
      echo "Signed source and Developer ID app/CLI/TUI verified."
      ;;
    publish)
      # CI never publishes. A local operator publish needs explicit approval
      # plus the same signed main/tag checks as every other release step.
      [[ "${PORTPILOT_NPM_PUBLISH_APPROVED:-}" == 1 && -z "${CI:-}" ]] || release_fail "automatic publishing is disabled; publish locally from signed main with PORTPILOT_NPM_PUBLISH_APPROVED=1"
      verify_release_source "${2:-}"
      echo "Signed main and tag $RELEASE_TAG verified for operator-approved npm publish."
      ;;
    *) release_fail "unknown policy mode: $mode" ;;
  esac
fi
