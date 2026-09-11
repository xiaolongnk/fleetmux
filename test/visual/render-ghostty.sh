#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: test/visual/render-ghostty.sh --config-file <path> --output <png>

Renders a deterministic fleetmux tmux fixture in a new Ghostty instance,
captures that exact window by CoreGraphics window id, removes the title bar,
and rejects empty/black output.
EOF
}

CONFIG_FILE=""
OUTPUT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --config-file) CONFIG_FILE="${2:-}"; shift 2 ;;
    --output) OUTPUT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'render-ghostty: unknown argument: %s\n' "$1" >&2; usage >&2; exit 64 ;;
  esac
done

[ -n "$CONFIG_FILE" ] || { printf 'render-ghostty: --config-file is required\n' >&2; exit 64; }
[ -n "$OUTPUT" ] || { printf 'render-ghostty: --output is required\n' >&2; exit 64; }
[ -f "$CONFIG_FILE" ] || { printf 'render-ghostty: config not found: %s\n' "$CONFIG_FILE" >&2; exit 66; }
[ "$(uname -s)" = Darwin ] || { printf 'render-ghostty: macOS is required (targeted Ghostty capture uses CoreGraphics)\n' >&2; exit 69; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GHOSTTY_BIN="${GHOSTTY_BIN:-/Applications/Ghostty.app/Contents/MacOS/ghostty}"
GHOSTTY_APP="${GHOSTTY_APP:-/Applications/Ghostty.app}"
for tool in swift swiftc magick open ditto codesign; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'render-ghostty: required tool not found: %s\n' "$tool" >&2; exit 69; }
done
[ -x "$GHOSTTY_BIN" ] || { printf 'render-ghostty: Ghostty binary not found: %s\n' "$GHOSTTY_BIN" >&2; exit 69; }
[ -d "$GHOSTTY_APP" ] || { printf 'render-ghostty: Ghostty app not found: %s\n' "$GHOSTTY_APP" >&2; exit 69; }

mkdir -p "$(dirname "$OUTPUT")"
OUTPUT="$(cd "$(dirname "$OUTPUT")" && pwd)/$(basename "$OUTPUT")"
CONFIG_FILE="$(cd "$(dirname "$CONFIG_FILE")" && pwd)/$(basename "$CONFIG_FILE")"

"$GHOSTTY_BIN" +validate-config --config-file="$CONFIG_FILE" >/dev/null
swift "$ROOT_DIR/test/visual/display-state.swift" >/dev/null

SCRATCH="$(mktemp -d /private/tmp/fleetmux-visual.XXXXXX)"
TOKEN="fleetmux-visual-$(basename "$SCRATCH")"
EFFECTIVE_CONFIG="$SCRATCH/ghostty.conf"
RAW_CAPTURE="$SCRATCH/window.png"
GHOSTTY_PID=""

cleanup() {
  if [ -n "$GHOSTTY_PID" ]; then kill "$GHOSTTY_PID" >/dev/null 2>&1 || true; fi
  rm -rf "$SCRATCH"
}
trap cleanup EXIT INT TERM

cp "$CONFIG_FILE" "$EFFECTIVE_CONFIG"
cat >>"$EFFECTIVE_CONFIG" <<EOF
title = $TOKEN
window-width = 100
window-height = 30
window-save-state = never
confirm-close-surface = false
macos-auto-secure-input = false
wait-after-command = true
EOF
"$GHOSTTY_BIN" +validate-config --config-file="$EFFECTIVE_CONFIG" >/dev/null

# A unique scratch bundle prevents the capture window from being routed into
# or confused with the owner's running Ghostty instance.
ISOLATED_APP="$SCRATCH/FleetmuxGhostty.app"
ditto "$GHOSTTY_APP" "$ISOLATED_APP"
BUNDLE_ID="dev.fleetmux.visual.${TOKEN//[^A-Za-z0-9]/}"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$ISOLATED_APP/Contents/Info.plist"
codesign --force --deep --sign - "$ISOLATED_APP" >/dev/null 2>&1

AFTER_WINDOWS="$SCRATCH/windows-after.txt"
open -n "$ISOLATED_APP" --args --config-file="$EFFECTIVE_CONFIG" \
  -e /bin/bash "$ROOT_DIR/test/visual/fixture-pane.sh" frame

ISOLATED_BIN="$(realpath "$ISOLATED_APP/Contents/MacOS/ghostty")"
for _ in $(seq 1 40); do
  GHOSTTY_PID="$(ps -axo pid=,command= | awk -v binary="$ISOLATED_BIN" '
    { pid=$1; $1=""; sub(/^ +/, ""); if (index($0, binary) == 1) print pid }
  ' | head -1)"
  [ -n "$GHOSTTY_PID" ] && break
  sleep 0.25
done
[ -n "$GHOSTTY_PID" ] || { printf 'render-ghostty: isolated Ghostty process did not start\n' >&2; exit 1; }

WINDOW_ROW=""
WINDOW_ERROR="$SCRATCH/window-error.txt"
for _ in $(seq 1 40); do
  swift "$ROOT_DIR/test/visual/window-id.swift" --list >"$AFTER_WINDOWS"
  MATCHING_IDS="$(awk -F '\t' -v pid="$GHOSTTY_PID" '$2 == pid { print $1 }' "$AFTER_WINDOWS")"
  if [ "$(printf '%s\n' "$MATCHING_IDS" | sed '/^$/d' | wc -l | tr -d ' ')" = 1 ]; then
    WINDOW_ID="$MATCHING_IDS"
    if WINDOW_ROW="$(swift "$ROOT_DIR/test/visual/window-id.swift" --id "$WINDOW_ID" 2>"$WINDOW_ERROR")"; then
      break
    fi
  fi
  sleep 0.25
done
[ -n "$WINDOW_ROW" ] || {
  printf 'render-ghostty: window lookup FAILED after 10s; expected one window owned by isolated Ghostty pid %s\n' "$GHOSTTY_PID" >&2
  printf 'render-ghostty: observed Ghostty window rows (id pid width height sharing):\n' >&2
  sed -n '1,10p' "$AFTER_WINDOWS" >&2
  if [ -f "$SCRATCH/attach.err" ]; then sed -n '1,5p' "$SCRATCH/attach.err" >&2; fi
  if [ -f "$WINDOW_ERROR" ]; then sed -n '1,3p' "$WINDOW_ERROR" >&2; fi
  exit 1
}

IFS=$'\t' read -r WINDOW_ID WINDOW_OWNER_PID BOUNDS_WIDTH BOUNDS_HEIGHT SHARING_STATE <<<"$WINDOW_ROW"
sleep 1

CAPTURE_BIN="$SCRATCH/capture-window"
swiftc -parse-as-library "$ROOT_DIR/test/visual/capture-window.swift" -o "$CAPTURE_BIN"
if ! "$CAPTURE_BIN" "$WINDOW_ID" "$RAW_CAPTURE"; then
  printf 'render-ghostty: capture FAILED for the verified Ghostty window id %s\n' "$WINDOW_ID" >&2
  exit 1
fi
[ -s "$RAW_CAPTURE" ] || { printf 'render-ghostty: capture FAILED: ScreenCaptureKit emitted an empty file\n' >&2; exit 1; }

read -r PIXEL_WIDTH PIXEL_HEIGHT <<<"$(magick identify -format '%w %h' "$RAW_CAPTURE")"
[ "$PIXEL_WIDTH" -ge 400 ] && [ "$PIXEL_HEIGHT" -ge 200 ] || {
  printf 'render-ghostty: capture FAILED: implausible image dimensions %sx%s\n' "$PIXEL_WIDTH" "$PIXEL_HEIGHT" >&2
  exit 1
}

# The CoreGraphics window capture includes the macOS title bar. Its 28-point
# height scales with the captured pixel width relative to the point bounds.
TITLEBAR_PIXELS=$((28 * PIXEL_WIDTH / BOUNDS_WIDTH))
CONTENT_HEIGHT=$((PIXEL_HEIGHT - TITLEBAR_PIXELS))
magick "$RAW_CAPTURE" -crop "${PIXEL_WIDTH}x${CONTENT_HEIGHT}+0+${TITLEBAR_PIXELS}" +repage "$OUTPUT"

read -r MEAN DEVIATION ENTROPY <<<"$(magick "$OUTPUT" -colorspace Gray -format '%[fx:mean] %[fx:standard_deviation] %[entropy]' info:)"
if ! awk -v mean="$MEAN" -v deviation="$DEVIATION" -v entropy="$ENTROPY" \
  'BEGIN { exit !(mean > 0.01 && deviation > 0.01 && entropy > 0.01) }'; then
  printf 'render-ghostty: capture FAILED: image is black/empty (mean=%s deviation=%s entropy=%s); display may be asleep\n' \
    "$MEAN" "$DEVIATION" "$ENTROPY" >&2
  rm -f "$OUTPUT"
  exit 1
fi

printf 'CAPTURE PASS window_id=%s owner=Ghostty owner_pid=%s sharing=%s bounds=%sx%s image=%sx%s mean=%s deviation=%s entropy=%s output=%s\n' \
  "$WINDOW_ID" "$WINDOW_OWNER_PID" "$SHARING_STATE" "$BOUNDS_WIDTH" "$BOUNDS_HEIGHT" \
  "$PIXEL_WIDTH" "$CONTENT_HEIGHT" "$MEAN" "$DEVIATION" "$ENTROPY" "$OUTPUT"
