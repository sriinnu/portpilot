#!/usr/bin/env bash
set -euo pipefail

# Package an already signed app; never read credentials, sign, contact Apple,
# replace an installed copy, or remove quarantine attributes automatically.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/release_policy.sh"
verify_release_source "${1:-}"
verify_release_artifacts app
package_release_artifacts app
