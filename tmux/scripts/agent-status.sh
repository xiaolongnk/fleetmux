#!/usr/bin/env bash
# agent-status.sh — probe running pane titles for known agent patterns.
# Called by tmux status-right every status-interval seconds.
# Output: compact coloured indicators for each detected agent, or empty string.
# Graceful-degradation: any pane-title fetch failure → silent, no output.

set -uo pipefail

pane_titles="$(tmux list-panes -a -F '#{pane_title}' 2>/dev/null || true)"

out=""

if echo "$pane_titles" | grep -qi 'claude\|claude-code'; then
  out="${out}#[fg=colour39]⬡ Claude#[fg=colour244] "
fi

if echo "$pane_titles" | grep -qi 'cursor'; then
  out="${out}#[fg=colour141]▣ Cursor#[fg=colour244] "
fi

if echo "$pane_titles" | grep -qi 'gemini'; then
  out="${out}#[fg=colour214]◈ Gemini#[fg=colour244] "
fi

printf '%s' "$out"
