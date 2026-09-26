#!/usr/bin/env bash
# Unit test for tmux/scripts/agent-status.sh: feed it real-world pane shapes through the
# FLEETMUX_PANES hook and assert what the status bar and the jump list would show.
# The fixtures are copied from a live tmux server running Claude Code + Codex crews, where
# the OLD title-only probe found 1 of 12 Claude panes and 0 of 16 Codex panes.
set -euo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)/tmux/scripts/agent-status.sh"
fail=0
check() { # check <label> <expected-substring-or-!substring> <actual>
  if [ "${2#!}" != "$2" ]; then
    if printf '%s' "$3" | grep -qF -- "${2#!}"; then echo "FAIL $1: found '${2#!}' in: $3"; fail=1; else echo "ok   $1"; fi
  else
    if printf '%s' "$3" | grep -qF -- "$2"; then echo "ok   $1"; else echo "FAIL $1: expected '$2' in: $3"; fail=1; fi
  fi
}

PANES=$'termio:1.1\tclaude.exe\t✳ Session resume
termio:1.2\tcodex\tReview delivery conformance | superX
termio:1.3\tnode\tCursor OK
termio:1.4\tcodex\t⠇ Handle tmux target send | superX
termio:2.2\tclaude\t✳ 线上数据库工作进度
termio:2.3\tfish\tsuperX
termio:3.1\t/usr/local/bin/claude\tclaude
termio:3.2\tnode\tgemini — ~/proj
termio:3.3\tpython3\tnotebook
termio:3.4\tcursor-agent\tsome task'

out="$(FLEETMUX_PANES="$PANES" bash "$S")"
check "claude counted by command, not title"   "⬡ Claude 3" "$out"
check "codex detected at all (was missing)"    "◆ Codex 2"  "$out"
check "gemini under node found via title"      "◈ Gemini 1" "$out"
check "cursor-agent by command + node/'Cursor OK' by title" "▣ Cursor 2" "$out"
check "plain fish/python panes not counted"    "!python"    "$out"

list="$(FLEETMUX_PANES="$PANES" bash "$S" --list claude)"
check "list claude → 3 targets" "3" "$(printf '%s\n' "$list" | wc -l | tr -d ' ')"
check "list carries the target for jumping"   "termio:2.2" "$list"
check "list excludes other agents"            "!codex"     "$list"

[ -z "$(FLEETMUX_PANES=$'a:1.1\tfish\tshell' bash "$S")" ] && echo "ok   empty output when nothing runs" || { echo "FAIL non-empty output"; fail=1; }

exit $fail
