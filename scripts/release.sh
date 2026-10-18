#!/usr/bin/env bash
# Cuts a release: bumps MARKETING_VERSION in Coreography.xcodeproj, updates the
# README <!-- version --> marker, commits, tags "v<version>", and with --push
# pushes branch + tag, triggering .github/workflows/release.yml to run the
# tests, build a universal ad-hoc-signed zip, and publish the GitHub Release.
# The tag is the source of truth for the released version.
#
#   scripts/release.sh 0.2.0          # bump MARKETING_VERSION + README, commit, tag v0.2.0
#   scripts/release.sh 0.2.0 --push   # …also push the commit + tag (CI then publishes)
#   scripts/release.sh                # tag the current MARKETING_VERSION as-is
#
# Usage: scripts/release.sh [X.Y[.Z]] [--push]
# Shared engine: https://github.com/L-K-M/release-tool (this stub only sets config).
set -euo pipefail

export RELEASE_APP_NAME="Coreography"
export RELEASE_KIND="xcode"
export RELEASE_XCODE_PROJECT="Coreography.xcodeproj"
export RELEASE_XCODE_SCHEME="Coreography"
export RELEASE_CI_NOTE="CI (release.yml) will now run the tests, build the universal ad-hoc-signed zip, and publish the GitHub Release for <tag>."
export RELEASE_INVOKED_AS="scripts/release.sh"

BIN="${LKM_RELEASE_BIN:-lkm-release}"
command -v "$BIN" >/dev/null 2>&1 || {
  echo "error: lkm-release not found; install https://github.com/L-K-M/release-tool" >&2
  exit 1
}
exec "$BIN" "$@"
