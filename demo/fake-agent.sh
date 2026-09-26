#!/usr/bin/env bash
# fake-agent.sh — stand-in for an agent CLI, used ONLY to record the README demo.
# Installed into a temp PATH under the real names (claude, codex, gemini) so fleetmux's
# probe detects it exactly the way it detects the real thing (by pane_current_command),
# and paints one of three screens the real CLIs show, so the state detection is exercised
# for real too. Nothing here talks to any model.
#
#   fake-agent.sh <display-name> <busy|idle|attention> <task>
set -u
name="$1"; state="$2"; task="${3:-}"
printf '\033]2;%s\033\\' "✳ $task"             # pane title = conversation topic, like Claude Code
trap 'exit 0' INT TERM

frame() {
  printf '\033[2J\033[H'
  printf '\033[1;36m%s\033[0m  \033[2m%s\033[0m\n\n' "$name" "$task"
  case "$state" in
    busy)
      printf '  \033[2m● Read src/auth/middleware.ts\033[0m\n'
      printf '  \033[2m● Edit src/auth/middleware.ts\033[0m\n'
      printf '  \033[2m● Bash(npm test -- auth)\033[0m\n\n'
      printf '  \033[33m%s\033[0m Running tests… \033[2m(esc to interrupt)\033[0m\n' "$1" ;;
    attention)
      printf '  \033[2m● Read package.json\033[0m\n\n'
      printf '  \033[1mBash\033[0m(rm -rf dist/ && npm run build)\n'
      printf '  \033[1mDo you want to proceed?\033[0m\n'
      printf '  \033[36m❯ 1. Yes\033[0m\n    2. Yes, and don'"'"'t ask again for rm -rf\n    3. No\n' ;;
    idle)
      printf '  \033[2m● Edit README.md\033[0m\n'
      printf '  \033[2m● Bash(git commit -m "docs: quickstart")\033[0m\n\n'
      printf '  \033[32m✓\033[0m Done — committed \033[2m3f9a1c2\033[0m. Anything else?\n\n'
      printf '  \033[2m>\033[0m \033[7m \033[0m\n' ;;
  esac
}

i=0; spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
while :; do
  frame "${spin:$((i % 10)):1}"
  i=$((i+1))
  sleep 0.12
done
