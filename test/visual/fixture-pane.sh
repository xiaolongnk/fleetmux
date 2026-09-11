#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = frame ]; then
  [ -n "${2:-}" ] || { printf 'fixture-pane: frame requires a sentinel\n' >&2; exit 64; }
fi

case "${1:-}" in
  frame)
    printf '\033[2J\033[H'
    printf '\033[1;37m%s\033[0m\n' "$2"
    printf '\033[1;36m%-66s\033[0m│ \033[1;36m%-30s\033[0m\n' 'Claude Code' 'Shell'
    printf '%-66s│ %-30s\n' '' ''
    printf '\033[1;32m$\033[0m %-64s│ \033[1;32m$\033[0m %-28s\n' 'claude' 'git status --short'
    printf '\033[1;35m%-66s\033[0m│ %-30s\n' '✻ Working on deterministic capture…' 'working tree clean'
    printf '\033[32m%-66s\033[0m│ %-30s\n' '✓ Tests passed' ''
    printf '%-66s│ \033[1;32m$\033[0m %-28s\n' 'Ready for next task.' 'tmux list-panes'
    printf '%-66s│ %-30s\n' '' '0  Claude Code'
    printf '%-66s│ %-30s\n' '' '1  Shell'
    for _ in $(seq 1 18); do printf '%-66s│ %-30s\n' '' ''; done
    printf '\033[48;5;236m\033[38;5;255m %-12s\033[1m%-28s\033[0m\033[48;5;236m\033[38;5;250m%-56s\033[0m\n' \
      'fleetmux' 'workspace' 'agents  ⬡ Claude  12:34  demo-host'
    ;;
  main)
    printf '\033[2J\033[H'
    printf '\033[1;36mfleetmux visual baseline\033[0m\n\n'
    printf '\033[1;32m$\033[0m claude\n'
    printf '\033[1;35m✻ Working on deterministic capture…\033[0m\n'
    printf '\033[32m✓ Tests passed\033[0m\n'
    printf 'Ready for next task.\n'
    ;;
  side)
    printf '\033[2J\033[H'
    printf '\033[1;36mshell\033[0m\n\n'
    printf '\033[1;32m$\033[0m git status --short\n'
    printf 'working tree clean\n\n'
    printf '\033[1;32m$\033[0m tmux list-panes\n'
    printf '0  Claude Code\n'
    printf '1  Shell\n'
    ;;
  *)
    printf 'fixture-pane: expected frame, main, or side\n' >&2
    exit 64
    ;;
esac

while :; do sleep 3600; done
