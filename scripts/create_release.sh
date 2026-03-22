#!/usr/bin/env bash
set -euo pipefail

# I bump PortPilot's version, validate the CLI package shape, push main, and publish a matching git tag.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_JSON="$ROOT_DIR/package.json"
INFO_PLIST="$ROOT_DIR/Sources/PortPilot/Info.plist"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: bash scripts/create_release.sh <version>" >&2
  echo "Example: bash scripts/create_release.sh 2.0.1" >&2
  exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
  echo "Version must look like 2.0.1 or 2.1" >&2
  exit 1
fi

cd "$ROOT_DIR"

CURRENT_BRANCH="$(git branch --show-current)"
if [[ "$CURRENT_BRANCH" != "main" ]]; then
  echo "Release script must run from main. Current branch: $CURRENT_BRANCH" >&2
  exit 1
fi

if [[ -n "$(git status --short)" ]]; then
  echo "Working tree is not clean. Commit or stash changes before releasing." >&2
  git status --short
  exit 1
fi

if git rev-parse --verify --quiet "refs/tags/v$VERSION" >/dev/null; then
  echo "Tag v$VERSION already exists." >&2
  exit 1
fi

echo "Updating package.json to $VERSION"
node -e '
const fs = require("fs");
const path = process.argv[1];
const version = process.argv[2];
const pkg = JSON.parse(fs.readFileSync(path, "utf8"));
pkg.version = version;
pkg.scripts.release = "npm run build:all && npm run install:app && npm run install:cli && echo '\''✓ PortPilot v" + version + " released!'\''";
fs.writeFileSync(path, JSON.stringify(pkg, null, 2) + "\n");
' "$PACKAGE_JSON" "$VERSION"

echo "Updating Info.plist to $VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$INFO_PLIST"

echo "Building CLI release"
swift build -c release

echo "Validating npm package payload"
mkdir -p .tmp/npm-cache-release
NPM_CONFIG_CACHE=.tmp/npm-cache-release npm pack --ignore-scripts --json >/dev/null
rm -rf .tmp

echo "Committing release version bump"
git add "$PACKAGE_JSON" "$INFO_PLIST"
git commit -m "Release v$VERSION"

echo "Pushing main"
git push origin main

echo "Creating and pushing tag v$VERSION"
git tag "v$VERSION"
git push origin "v$VERSION"

echo "Release submitted."
echo "GitHub release workflow and npm publish workflow should start from tag v$VERSION."
