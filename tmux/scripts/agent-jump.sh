#!/usr/bin/env bash
# agent-jump.sh [claude|codex|cursor|gemini|any|waiting] — cycle through the panes running that
# agent ("waiting" = any agent pane that is idle or asking for approval). Each press moves to the NEXT matching pane after the current one (wrapping), so
# with three Claude panes open, prefix+a visits all three in turn instead of always
# landing on the first. Bound in tmux.conf; uses the same probe as the status bar.
set -uo pipefail

want="${1:-any}"
[ "$want" = "any" ] && want=""
here="$(dirname "$0")"

targets="$("$here/agent-status.sh" --list "$want" | cut -f1)"
[ -n "$targets" ] || { tmux display-message "fleetmux: no ${1:-agent} pane running" 2>/dev/null; exit 0; }

current="$(tmux display-message -p '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null || true)"
next=""; first=""; take_next=false
while IFS= read -r t; do
  [ -n "$first" ] || first="$t"
  if $take_next; then next="$t"; break; fi
  [ "$t" = "$current" ] && take_next=true
done <<< "$targets"
[ -n "$next" ] || next="$first"

tmux switch-client -t "${next%%:*}" 2>/dev/null || true
tmux select-window -t "${next%.*}" 2>/dev/null || true
tmux select-pane -t "$next" 2>/dev/null || true
