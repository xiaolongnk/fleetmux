#!/usr/bin/env bash
# agent-status.sh — find the panes running AI coding agents, and whether each needs you.
#
#   agent-status.sh                 status-bar fragment, e.g. "⬡ Claude 12 ●3  ◆ Codex 16 ●1"
#                                   (●N = panes waiting for you; empty when no agent runs)
#   agent-status.sh --list [agent|waiting]
#                                   one line per agent pane: "<target>\t<agent>\t<state>\t<title>"
#                                   state: busy | attention | idle
#
# WHICH panes are agents: by the pane's running COMMAND (#{pane_current_command}) — Claude
# Code titles its pane with the conversation topic, Codex with the task, so titles are only
# consulted when the command is a generic runtime (node/bun/deno/python) wrapping a JS/Python
# agent such as Gemini CLI.
#
# WHAT STATE a pane is in: from the last lines on its screen (tmux capture-pane), because
# tmux has no per-pane activity clock and the agents all print the same tells:
#   busy       "esc to interrupt" / "esc to cancel" / a braille spinner  → still working
#   attention  "Do you want to proceed", "❯ 1. Yes", "(y/n)", "Allow"    → waiting for approval
#   idle       neither                                                    → waiting for input
# "waiting" = attention + idle: the panes where the next move is yours.
#
# Test hook: FLEETMUX_PANES replaces the tmux queries. Lines are
# "<target>\t<command>\t<title>\t<screen tail, newlines as \n>". Any tmux failure → empty.

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

# state <target> <screen-tail-or-empty> → busy | attention | idle
state() {
  local tail="$2"
  if [ -z "$tail" ] && [ -z "${FLEETMUX_PANES:-}" ]; then
    tail="$(tmux capture-pane -p -t "$1" -S -8 2>/dev/null || true)"
  fi
  # Literal alternation, not a bracket expression: bash 3.2 matches [⠋⠙…] byte-wise, so the
  # UTF-8 lead byte shared with ⏵/│ in Claude Code's status bar would flag every pane busy.
  if printf '%s' "$tail" | grep -qE 'esc to interrupt|esc to cancel|Esc to interrupt|⠋|⠙|⠹|⠸|⠼|⠴|⠦|⠧|⠇|⠏'; then
    echo busy
  # Anchored to the prompt's own shape (start of line / end of line) so a pane that merely
  # PRINTS these words — a log, a diff, someone grepping for them — is not "attention".
  elif printf '%s' "$tail" | grep -qE '^[[:space:]]*(Do you want to proceed|❯ 1\. Yes|Allow (once|always|this)|Approve\??[[:space:]]*$)|\((y/n|Y/n)\)[[:space:]]*:?[[:space:]]*$'; then
    echo attention
  else
    echo idle
  fi
}

n_claude=0; n_codex=0; n_cursor=0; n_gemini=0
w_claude=0; w_codex=0; w_cursor=0; w_gemini=0
while IFS=$'\t' read -r target cmd title tail; do
  [ -n "${target:-}" ] || continue
  agent="$(classify "${cmd:-}" "${title:-}")"
  [ -n "$agent" ] || continue
  st="$(state "$target" "$(printf '%b' "${tail:-}")")"
  if [ "$MODE" = "--list" ]; then
    case "$WANT" in
      "")       ;;
      waiting)  [ "$st" != busy ] || continue ;;
      *)        [ "$WANT" = "$agent" ] || continue ;;
    esac
    printf '%s\t%s\t%s\t%s\n' "$target" "$agent" "$st" "${title:-}"
    continue
  fi
  case "$agent" in
    claude) n_claude=$((n_claude+1)); [ "$st" = busy ] || w_claude=$((w_claude+1)) ;;
    codex)  n_codex=$((n_codex+1));   [ "$st" = busy ] || w_codex=$((w_codex+1)) ;;
    cursor) n_cursor=$((n_cursor+1)); [ "$st" = busy ] || w_cursor=$((w_cursor+1)) ;;
    gemini) n_gemini=$((n_gemini+1)); [ "$st" = busy ] || w_gemini=$((w_gemini+1)) ;;
  esac
done <<< "$panes"

[ "$MODE" = "--list" ] && exit 0

# "<icon> <Name> <total>" in the agent's colour, then "●<waiting>" in amber when any pane needs you.
frag() { # frag <colour> <icon+name> <total> <waiting>
  [ "$3" -gt 0 ] || return 0
  printf '#[fg=%s]%s %s' "$1" "$2" "$3"
  [ "$4" -gt 0 ] && printf ' #[fg=colour214,bold]●%s#[nobold]' "$4"
  printf '#[fg=colour244]  '
}
out="$(frag colour39 "⬡ Claude" $n_claude $w_claude)$(frag colour114 "◆ Codex" $n_codex $w_codex)$(frag colour141 "▣ Cursor" $n_cursor $w_cursor)$(frag colour214 "◈ Gemini" $n_gemini $w_gemini)"
printf '%s' "$out"
