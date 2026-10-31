#!/usr/bin/env bash
# Drives the CPU and space braids with real pointer and key events on a
# macOS GUI session and films them, so the interaction can be reviewed in
# motion from CI (this app is partly developed on Linux, where the UI
# cannot run).
# Fails when the app quits or crashes during the capture.
#
# Usage: tools/ui-capture/capture.sh <Coreography.app> <output directory>
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }
[[ $# -eq 2 ]] || die "usage: $0 <Coreography.app> <output directory>"
APP="$1"
OUT="$2"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
# Seconds of history before the interaction: a full minute window of strands.
WARMUP=55
# Long enough for every step in drive.swift.
RECORD=70

mkdir -p "$OUT/frames" "$OUT/shots"

place_window() {
  osascript -e 'tell application "System Events" to tell process "Coreography"
    set frontmost to true
    set position of window 1 to {0, 25}
    set size of window 1 to {1024, 743}
  end tell' || echo "warning: could not place the window"
}

# Room for the window: the Dock hides and the window fills the screen; the
# person's setting comes back afterwards.
DOCK_AUTOHIDE=false
[[ "$(defaults read com.apple.dock autohide 2>/dev/null)" = 1 ]] && DOCK_AUTOHIDE=true
defaults write com.apple.dock autohide -bool true
killall Dock 2>/dev/null || true

# Real, named work for the strands while history builds up: a browser
# benchmark and a compile. Both stop before the interaction, as when someone
# looks back at what just happened; this runner has three cores, and
# interaction under full load is a known sampling problem on main too.
open -g -a Safari "https://browserbench.org/Speedometer3.1/?startAutomatically=true" || true
(cd "$ROOT" && nice -n 15 swift build -c release --product coreo >"$OUT/load-build.log" 2>&1) &
LOAD=$!
stop_load() {
  pkill -P "$LOAD" 2>/dev/null || true
  kill "$LOAD" 2>/dev/null || true
  # Only this build's compilers: their arguments name this checkout.
  pkill -f "swift-frontend.*$ROOT" 2>/dev/null || true
  osascript -e 'tell application "Safari" to quit' 2>/dev/null || true
}
finish() {
  stop_load
  defaults write com.apple.dock autohide -bool "$DOCK_AUTOHIDE"
  killall Dock 2>/dev/null || true
}
trap finish EXIT

open "$APP"
for _ in $(seq 60); do
  pgrep -x Coreography >/dev/null && break
  sleep 1
done
pgrep -x Coreography >/dev/null || die "Coreography did not start"
sleep 3
place_window

# How long this Mac takes to answer for its audio output: the braid's
# sounds must never wait for it on the main thread.
swift "$HERE/audio-probe.swift" 2>&1 | tee "$OUT/audio-probe.log" || true

sleep "$WARMUP"
# Safari's strand stays as a recorded contribution of an app that has exited.
stop_load
sleep 3
# The app's own CPU every half second, to line up with the steps.
PID="$(pgrep -nx Coreography || true)"
[[ -n "$PID" ]] || die "Coreography quit during the warmup"
(while kill -0 "$PID" 2>/dev/null; do
  echo "$(date +%s.%N | cut -c1-14) $(ps -o %cpu= -p "$PID")"
  sleep 0.5
done) >"$OUT/cpu.log" 2>/dev/null &
SAMPLER=$!
screencapture -x -C -k -V "$RECORD" -R"0,25,1024,560" "$OUT/braid.mov" &
RECORDER=$!
sleep 1
echo "drive starts at $(date +%s.%N | cut -c1-14)" >"$OUT/clock.log"
swift "$HERE/drive.swift" "$OUT" 2>&1 | tee "$OUT/steps.log"
wait "$RECORDER" || echo "warning: the recording ended with an error"
kill "$SAMPLER" 2>/dev/null || true

pgrep -x Coreography >/dev/null || die "Coreography quit during the capture"
swift "$HERE/frames.swift" "$OUT/braid.mov" "$OUT/frames" 10 || echo "warning: no frames extracted"
ls -la "$OUT" "$OUT/shots"
