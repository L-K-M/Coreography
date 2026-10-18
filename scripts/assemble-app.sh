#!/usr/bin/env bash
# Assembles dist/Coreography.app: the BUILD_SWIFTPM_ASSEMBLE command behind
# scripts/build.sh. Owns the whole build + signing; the lkm-build engine wraps it
# with --clean/--run/--install/--zip/--dmg and the Finder reveal. Needed because
# the engine's xcode kind accepts no extra xcodebuild settings, and universal
# builds require explicit ARCHS.
#
# Usage: scripts/assemble-app.sh [--debug]
#   (the engine forwards --debug only; everything else arrives via the environment)
#
# Env:
#   COREO_ARCH   arm64 | x86_64 | universal (default: the host arch via uname -m)
#                universal builds a dual-slice binary: ARCHS="arm64 x86_64"
#
# The Xcode project's "Embed CLI" copy phase already places the coreo tool target
# at Contents/Helpers/coreo inside the bundle, so one `xcodebuild -scheme
# Coreography` produces app + embedded CLI. This script then stages the bundle to
# dist/, verifies the expected slices in BOTH the app and the helper (before the
# engine can zip/install a wrong-arch build), and re-signs ad-hoc inside-out.
set -euo pipefail
cd "$(dirname "$0")/.."

die() { echo "error: $*" >&2; exit 1; }

CONFIG="Release"
for arg in "$@"; do
  case "$arg" in
    --debug) CONFIG="Debug" ;;
    *) die "unknown option '$arg' (assemble-app.sh takes only --debug; set COREO_ARCH for the architecture)" ;;
  esac
done

COREO_ARCH="${COREO_ARCH:-$(uname -m)}"
case "$COREO_ARCH" in
  universal)      ARCHS="arm64 x86_64"; WANT="arm64 x86_64" ;;
  arm64|x86_64)   ARCHS="$COREO_ARCH";  WANT="$COREO_ARCH" ;;
  *) die "unknown COREO_ARCH '$COREO_ARCH' (expected arm64|x86_64|universal)." ;;
esac

command -v xcodebuild >/dev/null 2>&1 || \
  die "xcodebuild not found; select Xcode 26.6 on a Mac."

DERIVED="build"
APP_SRC="${DERIVED}/Build/Products/${CONFIG}/Coreography.app"
APP_DST="dist/Coreography.app"

echo "==> Building Coreography.app (${CONFIG}, ${COREO_ARCH})…"
xcodebuild build \
  -project Coreography.xcodeproj \
  -scheme Coreography \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  "ARCHS=${ARCHS}" \
  ONLY_ACTIVE_ARCH=NO

[[ -d "$APP_SRC" ]] || die "build finished but ${APP_SRC} is missing."

echo "==> Staging ${APP_DST}…"
mkdir -p dist
rm -rf "$APP_DST"
ditto "$APP_SRC" "$APP_DST"

# Every expected slice must be present: a thin helper inside a fat app (or vice
# versa) would only surface on the other architecture.
verify_arches() {
  local bin="$1" got a
  [[ -f "$bin" ]] || die "expected binary missing: ${bin}"
  got="$(lipo -archs "$bin" 2>/dev/null)" || die "lipo could not read ${bin}"
  for a in $WANT; do
    case " ${got} " in
      *" ${a} "*) ;;
      *) die "${bin} lacks the ${a} slice (has: ${got})." ;;
    esac
  done
  echo "  -- ${bin#dist/}: ${got}"
}

echo "==> Verifying architectures…"
verify_arches "$APP_DST/Contents/MacOS/Coreography"
verify_arches "$APP_DST/Contents/Helpers/coreo"

# Sign inside-out: the helper first, then the bundle seals it. Ad-hoc ("-") only;
# there are no Developer ID / notary credentials for this project. --options
# runtime keeps the hardened runtime the project enables at build time.
echo "==> Ad-hoc signing (helper, then bundle)…"
codesign --force --options runtime --sign - "$APP_DST/Contents/Helpers/coreo"
codesign --force --options runtime --sign - "$APP_DST"
codesign --verify --deep --strict --verbose=1 "$APP_DST"

echo "Built ${APP_DST} (${CONFIG}, ${COREO_ARCH})."
