#!/usr/bin/env bash
# firstrun-popup.sh — show a Quick Start popup exactly once, on the first tmux session.
# Triggered by the session-created hook in tmux.conf.
# Sentinel: ~/.config/tmux/.firstrun-done — delete it to see the popup again.

set -uo pipefail

CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tmux"
SENTINEL="$CONF_DIR/.firstrun-done"

[[ -f "$SENTINEL" ]] && exit 0
mkdir -p "$CONF_DIR"
touch "$SENTINEL"

# Brief pause: let the session finish initializing before the popup appears.
sleep 0.4

SHOW_SCRIPT="$CONF_DIR/scripts/firstrun-show.sh"

# Fall back gracefully if the show script isn't installed yet.
if [[ ! -x "$SHOW_SCRIPT" ]]; then
  tmux display-message "fleetmux: press prefix+? for the cheat sheet"
  exit 0
fi

tmux display-popup \
  -T " fleetmux Quick Start " \
  -w 66 -h 18 -E \
  "bash '$SHOW_SCRIPT'"
