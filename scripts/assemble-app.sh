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
# Coreography` produces the app, helpers and widget. This script stages the bundle to
# dist/, verifies the expected slices in every executable (before the
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

# macOS tells builds of one bundle apart by CFBundleVersion, not the marketing
# version: with a constant build number the widget gallery can keep an older
# release's widget list, and LaunchServices cannot tell which of two copies is
# newer. The release engine bumps only MARKETING_VERSION, so derive the build
# number from it here (X.Y.Z -> X*10000 + Y*100 + Z, e.g. 0.5.0 -> 500). Every
# release thereby outranks the others and the constant 1 that Xcode builds and
# releases up to 0.5.0 carry.
VERSIONS="$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \(.*\);$/\1/p' Coreography.xcodeproj/project.pbxproj | sort -u)"
[[ -n "$VERSIONS" && "$VERSIONS" != *$'\n'* ]] || \
  die "Coreography.xcodeproj must set exactly one MARKETING_VERSION (found: ${VERSIONS:-none})."
[[ "$VERSIONS" =~ ^([0-9]+)\.([0-9]+)(\.([0-9]+))?$ ]] || \
  die "MARKETING_VERSION '${VERSIONS}' is not X.Y[.Z]."
MINOR=$((10#${BASH_REMATCH[2]}))
PATCH=$((10#${BASH_REMATCH[4]:-0}))
(( MINOR < 100 && PATCH < 100 )) || \
  die "MARKETING_VERSION '${VERSIONS}' needs minor and patch below 100 to derive a build number."
BUILD_NUMBER=$((10#${BASH_REMATCH[1]} * 10000 + MINOR * 100 + PATCH))

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
  "CURRENT_PROJECT_VERSION=${BUILD_NUMBER}" \
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
verify_arches "$APP_DST/Contents/MacOS/CoreographyHelper"
WIDGET="$APP_DST/Contents/PlugIns/CoreographyWidgets.appex"
verify_arches "$WIDGET/Contents/MacOS/CoreographyWidgets"
WIDGET_POINT="$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$WIDGET/Contents/Info.plist")" \
  || die "the desktop widget's Info.plist or extension point is missing."
[[ "$WIDGET_POINT" == com.apple.widgetkit-extension ]] || die "the desktop widget extension point is missing."
# An extension's build number must match its host app's.
for plist in "$APP_DST/Contents/Info.plist" "$WIDGET/Contents/Info.plist"; do
  bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" \
    || die "${plist#dist/} has no CFBundleVersion."
  [[ "$bundle_version" == "$BUILD_NUMBER" ]] || \
    die "${plist#dist/} has build ${bundle_version}, expected ${BUILD_NUMBER}."
done
HELPER_PLIST="$APP_DST/Contents/Library/LaunchDaemons/ch.lkmc.Coreography.helper.plist"
[[ -f "$HELPER_PLIST" ]] || die "the helper's launch daemon definition is missing."
plutil -lint "$HELPER_PLIST" >/dev/null || die "the helper's launch daemon definition is malformed."

# Sign inside-out: helpers and the widget first, then the bundle seals them. Ad-hoc ("-") only;
# there are no Developer ID / notary credentials for this project. --options
# runtime keeps the hardened runtime the project enables at build time.
echo "==> Ad-hoc signing (helpers, widget, then bundle)…"
codesign --force --options runtime --sign - "$APP_DST/Contents/Helpers/coreo"
# The app pins this identifier, so it is stated rather than derived.
codesign --force --options runtime --identifier ch.lkmc.Coreography.helper \
  --sign - "$APP_DST/Contents/MacOS/CoreographyHelper"
# Re-signing must retain the sandbox entitlement or WidgetKit cannot launch it.
WIDGET_ENTITLEMENTS=Widgets/CoreographyWidgets.entitlements
[[ -f "$WIDGET_ENTITLEMENTS" ]] || die "the widget entitlements file is missing."
codesign --force --options runtime --generate-entitlement-der --entitlements "$WIDGET_ENTITLEMENTS" \
  --sign - "$WIDGET"
# Both CI and releases use this adapter; verify the final signature before either packages it.
SIGNED_ENTITLEMENTS="$(mktemp -t coreography-widget-entitlements)"
trap 'rm -f "$SIGNED_ENTITLEMENTS"' EXIT
codesign --display --entitlements - --xml "$WIDGET" > "$SIGNED_ENTITLEMENTS"
WIDGET_SANDBOX="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$SIGNED_ENTITLEMENTS")" \
  || die "the signed widget has no sandbox entitlement."
[[ "$WIDGET_SANDBOX" == true ]] || die "the signed widget is not sandboxed."
rm -f "$SIGNED_ENTITLEMENTS"
trap - EXIT
codesign --force --options runtime --sign - "$APP_DST"
codesign --verify --deep --strict --verbose=1 "$APP_DST"

echo "Built ${APP_DST} (${CONFIG}, ${COREO_ARCH})."
