#!/usr/bin/env bash
# Builds Coreography.app from the command line and reveals it in Finder on success.
# Incremental Release build for the host architecture by default; --universal builds
# both slices (arm64 + x86_64). --clean resets wedged build daemons and wipes
# .build/ + build/ + dist/ before building. Thin adapter over the shared lkm-build
# engine (swiftpm kind): scripts/assemble-app.sh owns the xcodebuild invocation and
# signing, the engine wraps it with clean/run/install/zip/dmg and the Finder reveal.
#
# Usage: scripts/build.sh [--universal] [--clean] [--debug] [--run] [--install]
#                         [--zip] [--dmg] [--no-reveal] | --check | --help
#
# The engine has no --universal flag and accepts no extra xcodebuild settings, so
# this adapter consumes --universal here and hands scripts/assemble-app.sh the
# architecture through the environment instead:
#
#   COREO_ARCH   arm64 | x86_64 | universal (default: the host arch)
#
# Only ad-hoc signing is supported (no Developer ID / notary credentials exist for
# this project), so --dev/--developer-id are rejected instead of silently ignored.
# When --zip produced a package it is renamed to the fleet convention:
# dist/Coreography-v<version>-macos-<arch>.zip.
#
# Shared engine: https://github.com/L-K-M/release-tool (this stub only sets config).
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

# The engine cds to the repo root before doing anything; do the same so the
# zip-rename glob below resolves no matter where the stub was invoked from.
cd "$(dirname "$0")/.."

export BUILD_APP_NAME="Coreography"
export BUILD_PRODUCT_NAME="Coreography"
export BUILD_KIND="swiftpm"
export BUILD_SWIFTPM_ASSEMBLE="scripts/assemble-app.sh"
export BUILD_PRODUCT_PATH="dist/Coreography.app"
export BUILD_OUTPUT_DIR="dist"
export BUILD_CLEAN_PATHS=".build build dist"
export BUILD_INVOKED_AS="scripts/build.sh"

COREO_ARCH="${COREO_ARCH:-$(uname -m)}"
WANT_ZIP=false
MUTATES=true
ENGINE_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --universal)          COREO_ARCH="universal" ;;
    --zip)                WANT_ZIP=true; ENGINE_ARGS+=("$arg") ;;
    --dev|--developer-id) die "signing mode '${arg#--}' is not supported; this build only ad-hoc signs." ;;
    --app-version|--build) die "version overrides are not supported; use the Xcode project version and scripts/release.sh." ;;
    --check|--help|-h|--version) MUTATES=false; ENGINE_ARGS+=("$arg") ;;
    *)                    ENGINE_ARGS+=("$arg") ;;
  esac
done

case "$COREO_ARCH" in
  arm64|x86_64|universal) ;;
  *) die "unknown COREO_ARCH '$COREO_ARCH' (expected arm64|x86_64|universal)." ;;
esac
export COREO_ARCH

# An exported BUILD_SIGN_MODE other than adhoc would be ignored by the assemble
# script; fail rather than produce an ad-hoc build the caller thinks is
# something else.
case "${BUILD_SIGN_MODE:-adhoc}" in
  adhoc) ;;
  *) die "BUILD_SIGN_MODE='${BUILD_SIGN_MODE}' is not supported; only ad-hoc signing is available." ;;
esac

BIN="${LKM_BUILD_BIN:-lkm-build}"
command -v "$BIN" >/dev/null 2>&1 || {
  echo "error: lkm-build not found; install https://github.com/L-K-M/release-tool" >&2
  exit 1
}

# --check can't show the arch (the engine never sees --universal); say it here.
if ! $MUTATES; then echo "scripts/build.sh: arch=${COREO_ARCH} (env COREO_ARCH)"; fi

# Not exec: after a successful --zip build we rename the package to the fleet
# convention. --check/--help/--version exit inside the engine, so they still
# mutate nothing; renaming runs only after a build.
"$BIN" ${ENGINE_ARGS[@]+"${ENGINE_ARGS[@]}"}

if $WANT_ZIP && $MUTATES; then
  # Use the built product, never an mtime guess among older archives.
  ver="$(python3 - "$BUILD_PRODUCT_PATH/Contents/Info.plist" <<'PY'
import plistlib, re, sys
with open(sys.argv[1], "rb") as source:
    version = plistlib.load(source)["CFBundleShortVersionString"]
if not isinstance(version, str) or not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", version):
    raise SystemExit("Invalid built app version")
print(version)
PY
)" || die "could not read the built app version."
  source_zip="dist/Coreography-${ver}.zip"
  [[ -f "$source_zip" ]] || die "engine did not produce ${source_zip}."
  dst="dist/Coreography-v${ver}-macos-${COREO_ARCH}.zip"
  mv "$source_zip" "$dst"
  echo "Packaged ${dst}."
fi
