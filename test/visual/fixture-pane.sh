#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = frame ]; then
  [ -n "${2:-}" ] || { printf 'fixture-pane: frame requires a sentinel\n' >&2; exit 64; }
fi

case "${1:-}" in
  frame)
    [ -n "${FLEETMUX_TMUX_CONFIG:-}" ] || { printf 'fixture-pane: FLEETMUX_TMUX_CONFIG is required\n' >&2; exit 64; }
    [ -n "${FLEETMUX_TMUX_SOCKET:-}" ] || { printf 'fixture-pane: FLEETMUX_TMUX_SOCKET is required\n' >&2; exit 64; }
    script_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    tmux -L "$FLEETMUX_TMUX_SOCKET" -f "$FLEETMUX_TMUX_CONFIG" new-session -d \
      -s fleetmux -n workspace /bin/bash "$script_path" left "$2"
    tmux -L "$FLEETMUX_TMUX_SOCKET" split-window -h -l 38 \
      /bin/bash "$script_path" right
    tmux -L "$FLEETMUX_TMUX_SOCKET" select-pane -t 'fleetmux:1.1' -T 'Claude Code'
    tmux -L "$FLEETMUX_TMUX_SOCKET" select-pane -t 'fleetmux:1.2' -T 'Shell'
    tmux -L "$FLEETMUX_TMUX_SOCKET" select-pane -t 'fleetmux:1.1'
    exec tmux -L "$FLEETMUX_TMUX_SOCKET" attach-session -t fleetmux
    ;;
  left)
    printf '\033[2J\033[H\033[1;37m%s\033[0m\n' "$2"
    printf '\033[1;36mClaude Code — demo-lab\033[0m\n'
    printf '\033[34m~/demo-lab/src/agent.ts\033[0m\n'
    printf '\033[35mconst\033[0m agents \033[36m=\033[0m [\n'
    printf '  { name: \033[32m"Atlas"\033[0m, state: \033[32m"running"\033[0m },\n'
    printf '  { name: \033[32m"Mira"\033[0m, state: \033[32m"review"\033[0m },\n'
    printf '\033[36m];\033[0m\n\n'
    printf '\033[35mexport async function\033[0m \033[36mmonitor\033[0m() {\n'
    printf '  \033[35mconst\033[0m active \033[36m=\033[0m agents.\033[36mfilter\033[0m(isRunning);\n'
    printf '  \033[35mawait\033[0m \033[36mwatch\033[0m(active);\n'
    printf '  \033[35mreturn\033[0m { healthy: \033[33mtrue\033[0m };\n}\n\n'
    printf '\033[1;32m$\033[0m git diff -- src/agent.ts\n'
    printf '\033[1;35mdiff --git a/src/agent.ts b/src/agent.ts\033[0m\n'
    printf '\033[36m@@ -8,2 +8,2 @@ monitor()\033[0m\n'
    printf '\033[31m-  retry: 2,\033[0m\n\033[32m+  retry: 3,\033[0m\n\n'
    printf '\033[1;35m✻ Updating agent monitor…\033[0m\n'
    printf '\033[1;32m✓ 12 tests passed\033[0m\nReady for review.\n'
    ;;
  right)
    printf '\033[2J\033[H\033[1;36mShell — feature/agent-view\033[0m\n'
    printf '\033[1;32m$\033[0m git status --short --branch\n'
    printf '\033[35m## feature/agent-view\033[0m\n'
    printf '\033[31m M src/agent.ts\033[0m\n\033[31m M tests/agent.test.ts\033[0m\n'
    printf '\033[33m?? docs/preview.md\033[0m\n\n'
    printf '\033[1;32m$\033[0m ls -F\n'
    printf 'README.md  \033[33mpackage.json\033[0m\n'
    printf '\033[34msrc/\033[0m       \033[34mtests/\033[0m\n'
    printf '\033[34mscripts/\033[0m   \033[35mpreview.png\033[0m\n\n'
    printf '\033[1;32m$\033[0m npm test\n'
    printf '\033[1;33mWARN\033[0m retry budget near limit\n'
    printf '\033[1;31mERROR\033[0m 1 snapshot needs update\n\n'
    printf 'Tests:  \033[32m11 passed\033[0m, \033[31m1 failed\033[0m\n'
    printf '\033[90mTime:   0.84s\033[0m\n\n'
    printf '\033[1;32m$\033[0m npm test -- --update\n'
    printf '\033[1;32mPASS\033[0m tests/agent.test.ts\n'
    printf '\033[90mworking tree clean\033[0m\n'
    ;;
  prompt)
    [ -n "${STARSHIP_CONFIG:-}" ] || { printf 'fixture-pane: STARSHIP_CONFIG is required\n' >&2; exit 64; }
    command -v starship >/dev/null 2>&1 || { printf 'fixture-pane: starship is required\n' >&2; exit 69; }
    command -v fish >/dev/null 2>&1 || { printf 'fixture-pane: fish is required\n' >&2; exit 69; }
    width="${3:-100}"
    repo="${4:-}"
    [ -n "$repo" ] || { printf 'fixture-pane: prompt fixture requires a repo path\n' >&2; exit 64; }
    mkdir -p "$repo"
    git -C "$repo" init -q -b main
    git -C "$repo" config user.name 'Fleetmux Fixture'
    git -C "$repo" config user.email 'fixture@example.invalid'
    printf 'fleetmux\n' > "$repo/README.md"
    git -C "$repo" add README.md
    git -C "$repo" commit -qm 'fixture'
    printf 'prompt\n' >> "$repo/README.md"
    printf 'untracked\n' > "$repo/notes.txt"

    printf '\033[2J\033[H'
    printf '\033[1;37m%s\033[0m\n\n' "$2"
    printf '\033[1;35mAgent output streams above the prompt.\033[0m\n'
    printf 'Fixed repo: ~/work/fleetmux-demo\n\n'
    fish -c 'starship prompt $argv' -- --terminal-width="$width" --path="$repo" \
      --logical-path='~/work/fleetmux-demo' --status=0 --cmd-duration=2345
    printf 'git status --short\n'
    printf ' M README.md\n?? notes.txt\n\n'
    fish -c 'starship prompt $argv' -- --terminal-width="$width" --path="$repo" \
      --logical-path='~/work/fleetmux-demo' --status=17 --cmd-duration=213
    printf 'retry-agent --resume\n'
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
    printf 'fixture-pane: expected frame, prompt, left, right, main, or side\n' >&2
    exit 64
    ;;
esac

while :; do sleep 3600; done
