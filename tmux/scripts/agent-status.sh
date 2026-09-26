#!/usr/bin/env bash
# agent-status.sh — find the panes running AI coding agents.
#
#   agent-status.sh            status-bar fragment: "⬡ Claude 2  ◆ Codex 1" (empty if none)
#   agent-status.sh --list     one line per agent pane: "<target>\t<agent>\t<title>"
#   agent-status.sh --list claude   same, filtered to one agent (claude|codex|cursor|gemini)
#
# Detection is by the pane's running COMMAND (#{pane_current_command}), not its title:
# Claude Code sets the pane title to the conversation topic ("✳ Fix login bug"), Codex to
# the task, so titles only occasionally contain the agent's name. The title is consulted
# only when the command is a generic runtime (node/bun/deno/python) that could be wrapping
# a JS/Python agent CLI such as Gemini CLI.
#
# Test hook: FLEETMUX_PANES, when set, replaces the tmux query. Lines are
# "<target>\t<command>\t<title>". Graceful degradation: any tmux failure → empty output.

set -uo pipefail

MODE="${1:-}"
WANT="${2:-}"

if [ -n "${FLEETMUX_PANES:-}" ]; then
  panes="$FLEETMUX_PANES"
else
  panes="$(tmux list-panes -a -F $'#{session_name}:#{window_index}.#{pane_index}\t#{pane_current_command}\t#{pane_title}' 2>/dev/null || true)"
fi

# classify <command> <title> → agent name or ""
classify() {
  # bash 3.2 (macOS default) has no ${var,,} — lower-case with tr
  local cmd title
  cmd="$(printf '%s' "${1##*/}" | tr '[:upper:]' '[:lower:]')"; cmd="${cmd%.exe}"
  title="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
  case "$cmd" in
    claude|claude-code)        echo claude; return ;;
    codex|codex-cli)           echo codex;  return ;;
    cursor-agent|cursor)       echo cursor; return ;;
    gemini|gemini-cli)         echo gemini; return ;;
    node|bun|deno|python*|uv)  # generic runtime — the title is the only hint
      case "$title" in
        *claude*) echo claude ;;
        *codex*)  echo codex ;;
        *cursor*) echo cursor ;;
        *gemini*) echo gemini ;;
        *)        echo "" ;;
      esac; return ;;
  esac
  echo ""
}

n_claude=0; n_codex=0; n_cursor=0; n_gemini=0
while IFS=$'\t' read -r target cmd title; do
  [ -n "${target:-}" ] || continue
  agent="$(classify "${cmd:-}" "${title:-}")"
  [ -n "$agent" ] || continue
  if [ "$MODE" = "--list" ]; then
    [ -z "$WANT" ] || [ "$WANT" = "$agent" ] || continue
    printf '%s\t%s\t%s\n' "$target" "$agent" "${title:-}"
    continue
  fi
  case "$agent" in
    claude) n_claude=$((n_claude+1)) ;;
    codex)  n_codex=$((n_codex+1)) ;;
    cursor) n_cursor=$((n_cursor+1)) ;;
    gemini) n_gemini=$((n_gemini+1)) ;;
  esac
done <<< "$panes"

[ "$MODE" = "--list" ] && exit 0

out=""
[ "$n_claude" -gt 0 ] && out="${out}#[fg=colour39]⬡ Claude ${n_claude}#[fg=colour244]  "
[ "$n_codex"  -gt 0 ] && out="${out}#[fg=colour114]◆ Codex ${n_codex}#[fg=colour244]  "
[ "$n_cursor" -gt 0 ] && out="${out}#[fg=colour141]▣ Cursor ${n_cursor}#[fg=colour244]  "
[ "$n_gemini" -gt 0 ] && out="${out}#[fg=colour214]◈ Gemini ${n_gemini}#[fg=colour244]  "
printf '%s' "$out"
