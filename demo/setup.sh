#!/usr/bin/env bash
# Sourced by demo/demo.tape inside the vhs shell: builds an isolated tmux session with four
# fake agent panes and attaches to it. Uses the REPO's tmux.conf and scripts (not the
# machine's install) via a scratch HOME, so the recording never shows personal state.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
D="$(mktemp -d -t fleetmux-demo)"
export HOME="$D/home"
mkdir -p "$HOME/.config/tmux/scripts" "$HOME/.tmux/plugins/tpm/bin" "$D/bin"
# the shipped config minus the first-run popup hook (a recording has no tty for display-popup)
grep -v "set-hook -g session-created" "$REPO/tmux/tmux.conf" > "$HOME/.config/tmux/tmux.conf"
cp "$REPO/tmux/scripts/"*.sh "$HOME/.config/tmux/scripts/"
printf '#!/bin/sh\n' > "$HOME/.tmux/plugins/tpm/tpm"; chmod +x "$HOME/.tmux/plugins/tpm/tpm"   # TPM no-op
# tmux reports #{pane_current_command} from the process name, and a script's process name is
# its INTERPRETER — so each fake agent is a script whose interpreter is a bash copy named
# after the agent. That makes the probe detect it exactly as it detects the real binary.
mkdir -p "$D/interp"
BASH_BIN="$(command -v bash)"; [ -x /opt/homebrew/bin/bash ] && BASH_BIN=/opt/homebrew/bin/bash
for a in claude codex gemini; do
  cp "$BASH_BIN" "$D/interp/$a"
  printf '#!%s/interp/%s\n. "%s/demo/fake-agent.sh" "$@"\n' "$D" "$a" "$REPO" > "$D/bin/$a"; chmod +x "$D/bin/$a"
done
export PATH="$D/bin:$PATH"

S=demo
tmux -L "$S" kill-server 2>/dev/null
if [ "${FLEETMUX_DEMO_LAYOUT:-}" = vertical ]; then
  # phone-shaped recording (demo-vertical.tape): two panes stacked, bigger type
  tmux -L "$S" -f "$HOME/.config/tmux/tmux.conf" new-session -d -s agents -n agents -x 60 -y 60 \
    "claude 'Claude Code' attention 'Fix flaky build'"
  tmux -L "$S" split-window -v -t agents "codex 'Codex' busy 'Migrate settings table'"
  tmux -L "$S" split-window -v -t agents:agents.2 "codex 'Codex' idle 'Write quickstart docs'"
  tmux -L "$S" select-layout -t agents even-vertical
  # 60 columns: no session name on the left, no clock — the agent fragment is the point
  tmux -L "$S" set -g status-left ''
  tmux -L "$S" set -g window-status-format ''
  tmux -L "$S" set -g window-status-current-format ''
  tmux -L "$S" set -g status-right-length 58
  VERT_RIGHT='#(~/.config/tmux/scripts/agent-status.sh)'
else
  tmux -L "$S" -f "$HOME/.config/tmux/tmux.conf" new-session -d -s agents -n agents -x 150 -y 36 \
    "claude 'Claude Code' busy 'Refactor auth middleware'"
  tmux -L "$S" split-window -h -t agents "codex 'Codex' idle 'Write quickstart docs'"
  tmux -L "$S" split-window -v -t agents:agents.1 "claude 'Claude Code' attention 'Fix flaky build'"
  tmux -L "$S" split-window -v -t agents:agents.2 "codex 'Codex' busy 'Migrate settings table'"
  tmux -L "$S" select-layout -t agents tiled
fi
tmux -L "$S" select-pane -t agents:agents.1
tmux -L "$S" set -g status-interval 1
tmux -L "$S" set -g default-command "env PS1='~/work $ ' bash --norc --noprofile"   # clean prompt, no hostname
tmux -L "$S" set -g status-right "${VERT_RIGHT:-#(~/.config/tmux/scripts/agent-status.sh)#[fg=colour244] 14:02 #[fg=colour252]fleetmux }"
clear
exec tmux -L "$S" attach -t agents
