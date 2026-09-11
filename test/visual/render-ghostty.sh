#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: test/visual/render-ghostty.sh --config-file <path> --output <png> [options]

Options:
  --fixture frame|prompt   Fixture to render (default: frame)
  --starship-config PATH  Required for the prompt fixture
  --terminal-width COLS   Fixed prompt/window width (default: 100)
  --tmux-config-file PATH Shipped tmux config for the frame fixture
  --fixture-script PATH   Fixture implementation (default: repository fixture)

Renders a deterministic fleetmux tmux fixture in a new Ghostty instance,
captures that exact window by CoreGraphics window id, removes the title bar,
and rejects empty/black output.
EOF
}

CONFIG_FILE=""
OUTPUT=""
FIXTURE="frame"
STARSHIP_CONFIG=""
TMUX_CONFIG_FILE=""
FIXTURE_SCRIPT=""
TERMINAL_WIDTH=100
while [ "$#" -gt 0 ]; do
  case "$1" in
    --config-file) CONFIG_FILE="${2:-}"; shift 2 ;;
    --output) OUTPUT="${2:-}"; shift 2 ;;
    --fixture) FIXTURE="${2:-}"; shift 2 ;;
    --starship-config) STARSHIP_CONFIG="${2:-}"; shift 2 ;;
    --tmux-config-file) TMUX_CONFIG_FILE="${2:-}"; shift 2 ;;
    --fixture-script) FIXTURE_SCRIPT="${2:-}"; shift 2 ;;
    --terminal-width) TERMINAL_WIDTH="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'render-ghostty: unknown argument: %s\n' "$1" >&2; usage >&2; exit 64 ;;
  esac
done

[ -n "$CONFIG_FILE" ] || { printf 'render-ghostty: --config-file is required\n' >&2; exit 64; }
[ -n "$OUTPUT" ] || { printf 'render-ghostty: --output is required\n' >&2; exit 64; }
[ -f "$CONFIG_FILE" ] || { printf 'render-ghostty: config not found: %s\n' "$CONFIG_FILE" >&2; exit 66; }
[ "$FIXTURE" = frame ] || [ "$FIXTURE" = prompt ] || { printf 'render-ghostty: invalid fixture: %s\n' "$FIXTURE" >&2; exit 64; }
case "$TERMINAL_WIDTH" in *[!0-9]*|'') printf 'render-ghostty: terminal width must be numeric\n' >&2; exit 64 ;; esac
if [ "$FIXTURE" = prompt ]; then
  [ -f "$STARSHIP_CONFIG" ] || { printf 'render-ghostty: prompt fixture requires --starship-config\n' >&2; exit 66; }
  command -v starship >/dev/null 2>&1 || { printf 'render-ghostty: starship is required for prompt fixture\n' >&2; exit 69; }
  command -v fish >/dev/null 2>&1 || { printf 'render-ghostty: fish is required for prompt fixture\n' >&2; exit 69; }
fi
[ "$(uname -s)" = Darwin ] || { printf 'render-ghostty: macOS is required (targeted Ghostty capture uses CoreGraphics)\n' >&2; exit 69; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -z "$FIXTURE_SCRIPT" ]; then FIXTURE_SCRIPT="$ROOT_DIR/test/visual/fixture-pane.sh"; fi
[ -f "$FIXTURE_SCRIPT" ] || { printf 'render-ghostty: fixture script not found: %s\n' "$FIXTURE_SCRIPT" >&2; exit 66; }
if [ "$FIXTURE" = frame ]; then
  if [ -z "$TMUX_CONFIG_FILE" ]; then TMUX_CONFIG_FILE="$ROOT_DIR/tmux/tmux.conf"; fi
  [ -f "$TMUX_CONFIG_FILE" ] || { printf 'render-ghostty: tmux config not found: %s\n' "$TMUX_CONFIG_FILE" >&2; exit 66; }
fi
GHOSTTY_BIN="${GHOSTTY_BIN:-/Applications/Ghostty.app/Contents/MacOS/ghostty}"
GHOSTTY_APP="${GHOSTTY_APP:-/Applications/Ghostty.app}"
for tool in swift swiftc magick ditto codesign; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'render-ghostty: required tool not found: %s\n' "$tool" >&2; exit 69; }
done
if [ "$FIXTURE" = frame ]; then
  command -v tmux >/dev/null 2>&1 || { printf 'render-ghostty: required tool not found: tmux\n' >&2; exit 69; }
fi
[ -x "$GHOSTTY_BIN" ] || { printf 'render-ghostty: Ghostty binary not found: %s\n' "$GHOSTTY_BIN" >&2; exit 69; }
[ -d "$GHOSTTY_APP" ] || { printf 'render-ghostty: Ghostty app not found: %s\n' "$GHOSTTY_APP" >&2; exit 69; }

mkdir -p "$(dirname "$OUTPUT")"
OUTPUT="$(cd "$(dirname "$OUTPUT")" && pwd)/$(basename "$OUTPUT")"
CONFIG_FILE="$(cd "$(dirname "$CONFIG_FILE")" && pwd)/$(basename "$CONFIG_FILE")"
if [ -n "$STARSHIP_CONFIG" ]; then
  STARSHIP_CONFIG="$(cd "$(dirname "$STARSHIP_CONFIG")" && pwd)/$(basename "$STARSHIP_CONFIG")"
fi
FIXTURE_SCRIPT="$(cd "$(dirname "$FIXTURE_SCRIPT")" && pwd)/$(basename "$FIXTURE_SCRIPT")"
if [ "$FIXTURE" = frame ]; then
  TMUX_CONFIG_FILE="$(cd "$(dirname "$TMUX_CONFIG_FILE")" && pwd)/$(basename "$TMUX_CONFIG_FILE")"
fi

"$GHOSTTY_BIN" +validate-config --config-file="$CONFIG_FILE" >/dev/null
swift "$ROOT_DIR/test/visual/display-state.swift" >/dev/null

SCRATCH="$(mktemp -d /private/tmp/fleetmux-visual.XXXXXX)"
TOKEN="fleetmux-visual-$(basename "$SCRATCH")"
SENTINEL="FLEETMUX VISUAL FIXTURE"
EFFECTIVE_CONFIG="$SCRATCH/ghostty.conf"
RAW_CAPTURE="$SCRATCH/window.png"
EFFECTIVE_TMUX_CONFIG="$SCRATCH/tmux.conf"
FIXTURE_LAUNCHER="$SCRATCH/launch-fixture.sh"
GHOSTTY_PID=""

mkdir -p "$SCRATCH/home" "$SCRATCH/xdg-config"

cleanup() {
  if [ -n "$GHOSTTY_PID" ]; then kill "$GHOSTTY_PID" >/dev/null 2>&1 || true; fi
  tmux -L "$TOKEN" kill-server >/dev/null 2>&1 || true
  rm -rf "$SCRATCH"
}
trap cleanup EXIT INT TERM

cp "$CONFIG_FILE" "$EFFECTIVE_CONFIG"
cat >>"$EFFECTIVE_CONFIG" <<EOF
title = $TOKEN
window-width = $TERMINAL_WIDTH
window-height = 30
window-save-state = never
confirm-close-surface = false
macos-auto-secure-input = false
wait-after-command = true
EOF

printf '#!/usr/bin/env bash\nexec /bin/bash %q %q %q %q %q\n' \
  "$FIXTURE_SCRIPT" "$FIXTURE" "$SENTINEL" "$TERMINAL_WIDTH" "$SCRATCH/repo" >"$FIXTURE_LAUNCHER"
chmod +x "$FIXTURE_LAUNCHER"
printf 'command = %s\n' "$FIXTURE_LAUNCHER" >>"$EFFECTIVE_CONFIG"
"$GHOSTTY_BIN" +validate-config --config-file="$EFFECTIVE_CONFIG" >/dev/null

if [ "$FIXTURE" = frame ]; then
  cp "$TMUX_CONFIG_FILE" "$EFFECTIVE_TMUX_CONFIG"
  sed -i '' \
    -e 's|#(~/.tmux/plugins/tmux-continuum/scripts/continuum_save.sh)||' \
    -e 's|#(~/.config/tmux/scripts/agent-status.sh 2>/dev/null)|agents  ⬡ Claude |' \
    -e 's|%H:%M|12:34|' \
    -e 's|#h|demo-host|' \
    "$EFFECTIVE_TMUX_CONFIG"
  cat >>"$EFFECTIVE_TMUX_CONFIG" <<'EOF'

# Visual-harness overrides: tmux draws the chrome, but volatile host/time and
# external plugin probes above are replaced with fixed public fixture values.
# Preserve the source config's colour directives so comparisons exercise them.
set -g status-interval 0
set-hook -gu session-created
EOF
fi

# A unique scratch bundle prevents the capture window from being routed into
# or confused with the owner's running Ghostty instance.
ISOLATED_APP="$SCRATCH/FleetmuxGhostty.app"
ditto "$GHOSTTY_APP" "$ISOLATED_APP"
BUNDLE_ID="dev.fleetmux.visual.${TOKEN//[^A-Za-z0-9]/}"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$ISOLATED_APP/Contents/Info.plist"
codesign --force --deep --sign - "$ISOLATED_APP" >/dev/null 2>&1

ISOLATED_BIN="$(realpath "$ISOLATED_APP/Contents/MacOS/ghostty")"
AFTER_WINDOWS="$SCRATCH/windows-after.txt"
env HOME="$SCRATCH/home" XDG_CONFIG_HOME="$SCRATCH/xdg-config" SHELL=/bin/bash \
  STARSHIP_CONFIG="$STARSHIP_CONFIG" STARSHIP_SHELL=fish \
  FLEETMUX_TMUX_CONFIG="$EFFECTIVE_TMUX_CONFIG" FLEETMUX_TMUX_SOCKET="$TOKEN" \
  "$ISOLATED_BIN" --config-default-files=false --config-file="$EFFECTIVE_CONFIG" \
  >"$SCRATCH/ghostty.stdout" 2>"$SCRATCH/ghostty.stderr" &
GHOSTTY_PID=$!

WINDOW_ROW=""
WINDOW_ERROR="$SCRATCH/window-error.txt"
PADDING_X="$(awk -F= '
  /^[[:space:]]*window-padding-x[[:space:]]*=/ {
    value=$2; gsub(/[[:space:]]/, "", value); if (value ~ /^[0-9]+$/) found=value
  }
  END { if (found != "") print found }
' "$EFFECTIVE_CONFIG")"
PADDING_Y="$(awk -F= '
  /^[[:space:]]*window-padding-y[[:space:]]*=/ {
    value=$2; gsub(/[[:space:]]/, "", value); if (value ~ /^[0-9]+$/) found=value
  }
  END { if (found != "") print found }
' "$EFFECTIVE_CONFIG")"
PADDING_X="${PADDING_X:-2}"
PADDING_Y="${PADDING_Y:-2}"
# Ghostty's macOS window bounds use two points per configured padding unit on
# this Retina fixture; the terminal cell grid is a fixed 8x18 points.
EXPECTED_BOUNDS_WIDTH=$((TERMINAL_WIDTH * 8 + PADDING_X * 4))
EXPECTED_BOUNDS_HEIGHT=$((30 * 18 + PADDING_Y * 4 + 2))
BOUNDS_TOLERANCE=24
for _ in $(seq 1 40); do
  swift "$ROOT_DIR/test/visual/window-id.swift" --list >"$AFTER_WINDOWS"
  MATCHING_IDS="$(awk -F '\t' -v pid="$GHOSTTY_PID" -v expected_width="$EXPECTED_BOUNDS_WIDTH" \
    -v expected_height="$EXPECTED_BOUNDS_HEIGHT" -v tolerance="$BOUNDS_TOLERANCE" '
    function abs(value) { return value < 0 ? -value : value }
    $2 == pid && abs($3 - expected_width) <= tolerance && abs($4 - expected_height) <= tolerance { print $1 }
  ' "$AFTER_WINDOWS")"
  if [ "$(printf '%s\n' "$MATCHING_IDS" | sed '/^$/d' | wc -l | tr -d ' ')" = 1 ]; then
    WINDOW_ID="$MATCHING_IDS"
    if WINDOW_ROW="$(swift "$ROOT_DIR/test/visual/window-id.swift" --id "$WINDOW_ID" \
      --expected-width "$EXPECTED_BOUNDS_WIDTH" --expected-height "$EXPECTED_BOUNDS_HEIGHT" \
      --tolerance "$BOUNDS_TOLERANCE" 2>"$WINDOW_ERROR")"; then
      break
    fi
  fi
  sleep 0.25
done
[ -n "$WINDOW_ROW" ] || {
  printf 'render-ghostty: window lookup FAILED after 10s; expected one window owned by isolated Ghostty pid %s\n' "$GHOSTTY_PID" >&2
  printf 'render-ghostty: observed Ghostty window rows (id pid width height sharing):\n' >&2
  sed -n '1,10p' "$AFTER_WINDOWS" >&2
  sed -n '1,10p' "$SCRATCH/ghostty.stderr" >&2
  if [ -f "$SCRATCH/attach.err" ]; then sed -n '1,5p' "$SCRATCH/attach.err" >&2; fi
  if [ -f "$WINDOW_ERROR" ]; then sed -n '1,3p' "$WINDOW_ERROR" >&2; fi
  exit 1
}

IFS=$'\t' read -r WINDOW_ID WINDOW_OWNER_PID BOUNDS_WIDTH BOUNDS_HEIGHT SHARING_STATE <<<"$WINDOW_ROW"
sleep 3

CAPTURE_BIN="$SCRATCH/capture-window"
swiftc -parse-as-library "$ROOT_DIR/test/visual/capture-window.swift" -o "$CAPTURE_BIN"
if ! "$CAPTURE_BIN" "$WINDOW_ID" "$RAW_CAPTURE"; then
  printf 'render-ghostty: capture FAILED for the verified Ghostty window id %s\n' "$WINDOW_ID" >&2
  exit 1
fi
[ -s "$RAW_CAPTURE" ] || { printf 'render-ghostty: capture FAILED: ScreenCaptureKit emitted an empty file\n' >&2; exit 1; }

swift "$ROOT_DIR/test/visual/assert-fixture.swift" "$RAW_CAPTURE" "$SENTINEL" >/dev/null || {
  if [ "${FLEETMUX_KEEP_REJECTED_CAPTURE:-0}" = 1 ]; then
    cp "$RAW_CAPTURE" "${OUTPUT%.png}-rejected.png"
    printf 'render-ghostty: kept rejected capture at %s\n' "${OUTPUT%.png}-rejected.png" >&2
  fi
  printf 'render-ghostty: capture FAILED: selected Ghostty window is not the fixture terminal\n' >&2
  exit 1
}

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

printf 'CAPTURE PASS config_isolated=yes fixture_sentinel=yes window_id=%s owner=Ghostty owner_pid=%s sharing=%s bounds=%sx%s image=%sx%s mean=%s deviation=%s entropy=%s output=%s\n' \
  "$WINDOW_ID" "$WINDOW_OWNER_PID" "$SHARING_STATE" "$BOUNDS_WIDTH" "$BOUNDS_HEIGHT" \
  "$PIXEL_WIDTH" "$CONTENT_HEIGHT" "$MEAN" "$DEVIATION" "$ENTROPY" "$OUTPUT"
