#!/usr/bin/env bash
# Unit test for tmux/scripts/agent-status.sh: feed it real-world pane shapes through the
# FLEETMUX_PANES hook and assert what the status bar and the jump list would show.
# Fixtures are copied from a live tmux server running Claude Code + Codex crews, where the
# OLD title-only probe found 1 of 12 Claude panes and 0 of 16 Codex panes. The 4th field is
# the pane's screen tail (what `tmux capture-pane` returns), which decides busy/attention/idle.
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

BUSY_CLAUDE='  Thinking… (esc to interrupt)\n  ⏵⏵ bypass permissions on'
IDLE_CLAUDE='  [Opus 5.5 (1M context)] │ superX git:(main*)\n  ⏵⏵ bypass permissions on · ← 6 agents'
BUSY_CODEX='• Working (8m 55s • esc to interrupt) · 1 background terminal running\n› Ask Codex to do anything'
IDLE_CODEX='  Worked for 5m 8s · 10:41\n› Ask Codex to do anything\n  weekly 16% left · 258K window'
ASK_CLAUDE='  Bash(rm -rf build/)\n  Do you want to proceed?\n  ❯ 1. Yes\n    2. No'

PANES=$'termio:1.1\tclaude.exe\t✳ Session resume\t'"$IDLE_CLAUDE"$'
termio:1.2\tcodex\tReview delivery conformance | superX\t'"$IDLE_CODEX"$'
termio:1.3\tnode\tCursor OK\t
termio:1.4\tcodex\t⠇ Handle tmux target send | superX\t'"$BUSY_CODEX"$'
termio:2.2\tclaude\t✳ 线上数据库工作进度\t'"$BUSY_CLAUDE"$'
termio:2.3\tfish\tsuperX\t
termio:3.1\t/usr/local/bin/claude\tclaude\t'"$ASK_CLAUDE"$'
termio:3.2\tnode\tgemini — ~/proj\t
termio:3.3\tpython3\tnotebook\t
termio:3.4\tcursor-agent\tsome task\t'

out="$(FLEETMUX_PANES="$PANES" bash "$S")"
check "claude counted by command, not title"    "⬡ Claude 3" "$out"
check "claude: 2 of 3 waiting (idle + approval)" "⬡ Claude 3 #[fg=colour214,bold]●2" "$out"
check "codex detected at all (was missing)"     "◆ Codex 2"  "$out"
check "codex: 1 of 2 waiting"                   "◆ Codex 2 #[fg=colour214,bold]●1" "$out"
check "gemini under node found via title"       "◈ Gemini 1" "$out"
check "cursor-agent by command + node/'Cursor OK' by title" "▣ Cursor 2" "$out"
check "plain fish/python panes not counted"     "!python"    "$out"

list="$(FLEETMUX_PANES="$PANES" bash "$S" --list claude)"
check "list claude → 3 targets" "3" "$(printf '%s\n' "$list" | wc -l | tr -d ' ')"
check "list carries the target for jumping"    "termio:2.2" "$list"
check "list excludes other agents"             "!codex"     "$list"
check "busy state from 'esc to interrupt'"     $'termio:2.2\tclaude\tbusy' "$list"
check "attention state from approval prompt"   $'termio:3.1\tclaude\tattention' "$list"
check "idle state otherwise"                   $'termio:1.1\tclaude\tidle' "$list"

waiting="$(FLEETMUX_PANES="$PANES" bash "$S" --list waiting)"
check "waiting list excludes busy panes"       "!termio:2.2" "$waiting"
check "waiting list excludes busy codex"       "!termio:1.4" "$waiting"
check "waiting list includes idle codex"       "termio:1.2"  "$waiting"
check "waiting list includes approval prompt"  "termio:3.1"  "$waiting"

[ -z "$(FLEETMUX_PANES=$'a:1.1\tfish\tshell\t' bash "$S")" ] && echo "ok   empty output when nothing runs" || { echo "FAIL non-empty output"; fail=1; }

exit $fail
