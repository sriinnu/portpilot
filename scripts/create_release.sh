#!/usr/bin/env bash
set -euo pipefail

# Local handoff only. Version changes, signed commits/tags and PR/main review
# happen separately; this entry point must never mutate or publish source.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/release_policy.sh"
verify_release_source "${1:-}"
verify_release_artifacts all
package_release_artifacts all
