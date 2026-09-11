#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = frame ]; then
  [ -n "${2:-}" ] || { printf 'fixture-pane: frame requires a sentinel\n' >&2; exit 64; }
fi

case "${1:-}" in
  frame)
    row() {
      local left_plain="$1" left_color="$2" right_plain="$3" right_color="$4"
      printf '%b' "$left_color"
      printf '%*s│ ' "$((66 - ${#left_plain}))" ''
      printf '%b' "$right_color"
      printf '%*s\n' "$((30 - ${#right_plain}))" ''
    }

    printf '\033[2J\033[H'
    printf '\033[1;37m%s\033[0m\n' "$2"
    row 'Claude Code — demo-lab' '\033[1;36mClaude Code — demo-lab\033[0m' 'Shell — feature/agent-view' '\033[1;36mShell — feature/agent-view\033[0m'
    row '~/demo-lab/src/agent.ts' '\033[34m~/demo-lab/src/agent.ts\033[0m' '$ git status --short --branch' '\033[1;32m$\033[0m git status --short --branch'
    row 'const agents = [' '\033[35mconst\033[0m agents \033[36m=\033[0m [' '## feature/agent-view' '\033[35m## feature/agent-view\033[0m'
    row '  { name: "Atlas", state: "running" },' '  { name: \033[32m"Atlas"\033[0m, state: \033[32m"running"\033[0m },' ' M src/agent.ts' '\033[31m M src/agent.ts\033[0m'
    row '  { name: "Mira", state: "review" },' '  { name: \033[32m"Mira"\033[0m, state: \033[32m"review"\033[0m },' ' M tests/agent.test.ts' '\033[31m M tests/agent.test.ts\033[0m'
    row '];' '\033[36m];\033[0m' '?? docs/preview.md' '\033[33m?? docs/preview.md\033[0m'
    row '' '' '' ''
    row 'export async function monitor() {' '\033[35mexport async function\033[0m \033[36mmonitor\033[0m() {' '$ ls -F' '\033[1;32m$\033[0m ls -F'
    row '  const active = agents.filter(isRunning);' '  \033[35mconst\033[0m active \033[36m=\033[0m agents.\033[36mfilter\033[0m(isRunning);' 'README.md  package.json' '\033[37mREADME.md\033[0m  \033[33mpackage.json\033[0m'
    row '  await watch(active);' '  \033[35mawait\033[0m \033[36mwatch\033[0m(active);' 'src/       tests/' '\033[34msrc/\033[0m       \033[34mtests/\033[0m'
    row '  return { healthy: true };' '  \033[35mreturn\033[0m { healthy: \033[33mtrue\033[0m };' 'scripts/   preview.png' '\033[34mscripts/\033[0m   \033[35mpreview.png\033[0m'
    row '}' '}' '' ''
    row '' '' '$ npm test' '\033[1;32m$\033[0m npm test'
    row '$ git diff -- src/agent.ts' '\033[1;32m$\033[0m git diff -- src/agent.ts' 'WARN retry budget near limit' '\033[1;33mWARN\033[0m retry budget near limit'
    row 'diff --git a/src/agent.ts b/src/agent.ts' '\033[1;35mdiff --git a/src/agent.ts b/src/agent.ts\033[0m' 'ERROR 1 snapshot needs update' '\033[1;31mERROR\033[0m 1 snapshot needs update'
    row '@@ -8,2 +8,2 @@ monitor()' '\033[36m@@ -8,2 +8,2 @@ monitor()\033[0m' '' ''
    row '-  retry: 2,' '\033[31m-  retry: 2,\033[0m' 'Tests:  11 passed, 1 failed' 'Tests:  \033[32m11 passed\033[0m, \033[31m1 failed\033[0m'
    row '+  retry: 3,' '\033[32m+  retry: 3,\033[0m' 'Time:   0.84s' '\033[90mTime:   0.84s\033[0m'
    row '' '' '' ''
    row '✻ Updating agent monitor…' '\033[1;35m✻ Updating agent monitor…\033[0m' '$ npm test -- --update' '\033[1;32m$\033[0m npm test -- --update'
    row '✓ 12 tests passed' '\033[1;32m✓ 12 tests passed\033[0m' 'PASS tests/agent.test.ts' '\033[1;32mPASS\033[0m tests/agent.test.ts'
    row 'Ready for review.' '\033[37mReady for review.\033[0m' 'working tree clean' '\033[90mworking tree clean\033[0m'
    row '' '' '' ''
    row '' '' '' ''
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
