#!/usr/bin/env bash
# Regression guard: tmux's DEFAULT WheelUpPane/WheelDownPane bindings (active
# whenever `mouse on`) fire `copy-mode -e` on any incidental scroll over an
# attached pane — trackpad rest, momentum jitter, a stray wheel tick. This
# repo's provisioned tmux.conf must keep `mouse on` (click-to-select-pane +
# drag-to-resize rely on it) while unbinding both wheel events so copy-mode
# is only ever reachable via a deliberate `prefix + [`.
#
# Usage: bash test/tmux-config-policy.sh   (run from anywhere; paths are
# resolved relative to this script's own location, not $PWD)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEETMUX_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
CONF="$FLEETMUX_REPO/tmux/tmux.conf"

if [ ! -f "$CONF" ]; then
  echo "FAIL — $CONF not found"
  exit 1
fi

if ! grep -qE '^\s*set -g mouse on\s*$' "$CONF"; then
  echo "FAIL — 'set -g mouse on' missing (click-to-select-pane + drag-to-resize need it)"
  exit 1
fi
echo "PASS (mouse mode stays on)"

if ! grep -qE '^\s*unbind -n WheelUpPane\s*$' "$CONF"; then
  echo "FAIL — 'unbind -n WheelUpPane' missing — a stray scroll-up would auto-enter copy-mode"
  exit 1
fi
echo "PASS (WheelUpPane unbound)"

if ! grep -qE '^\s*unbind -n WheelDownPane\s*$' "$CONF"; then
  echo "FAIL — 'unbind -n WheelDownPane' missing — a stray scroll-down would auto-enter copy-mode"
  exit 1
fi
echo "PASS (WheelDownPane unbound)"

# The unbinds must come AFTER `mouse on` (mouse mode has to be enabled before
# there's a WheelUpPane/WheelDownPane binding worth unbinding) — order proves
# this isn't a stray line accidentally landing before mouse mode is even on.
mouse_line="$(grep -nE '^\s*set -g mouse on\s*$' "$CONF" | head -1 | cut -d: -f1)"
wheel_up_line="$(grep -nE '^\s*unbind -n WheelUpPane\s*$' "$CONF" | head -1 | cut -d: -f1)"
wheel_down_line="$(grep -nE '^\s*unbind -n WheelDownPane\s*$' "$CONF" | head -1 | cut -d: -f1)"
if [ "$wheel_up_line" -le "$mouse_line" ] || [ "$wheel_down_line" -le "$mouse_line" ]; then
  echo "FAIL — wheel unbinds must appear after 'set -g mouse on' in $CONF"
  exit 1
fi
echo "PASS (unbinds ordered after mouse on)"

echo ""
echo "TMUX CONFIG POLICY TEST: PASS"
