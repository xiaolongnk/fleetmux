#!/usr/bin/env bash
# firstrun-show.sh — Quick Start content displayed inside a tmux display-popup.
# Called by firstrun-popup.sh with display-popup -E (popup closes when this exits).

cat << 'EOF'

  fleetmux — Quick Start                   prefix = Ctrl-q

  ─────────────────────────────────────────────────────────────
  MOUSE  (no prefix needed)

    Click a pane              Focus it
    Click a window tab        Switch to it
    Drag a pane border        Resize the pane
    Scroll wheel              Browse scrollback history

  ─────────────────────────────────────────────────────────────
  TOP SHORTCUTS

    prefix + |                Split pane left / right
    prefix + -                Split pane top / bottom
    prefix + z                Zoom / un-zoom current pane
    prefix + c                New window (tab)
    prefix + a                Jump to Claude Code pane
    prefix + ?                Open the full cheat sheet

  ─────────────────────────────────────────────────────────────
  Tip: delete ~/.config/tmux/.firstrun-done to see this again.

EOF
printf '  Press any key to dismiss… '
read -rsn1
