# Agent-Pane Detection

fleetmux's status bar and jump bindings work by probing **pane titles** in your
running tmux session. No daemon or background process is required.

---

## How pane-title detection works

Every 5 seconds, the `agent-status.sh` script runs inside tmux and executes:

```bash
tmux list-panes -a -F '#{pane_title}'
```

It scans the output for known agent name patterns (case-insensitive):

| Pattern matched | Indicator shown |
|-----------------|-----------------|
| `claude` or `claude-code` | `⬡ Claude` |
| `cursor` | `▣ Cursor` |
| `gemini` | `◈ Gemini` |

If no pane titles match any pattern, the status bar shows no agent indicators —
it degrades gracefully with no visual noise.

---

## How agents set their pane title

Most AI agent CLIs set the tmux pane title automatically when they start:

| Agent | Pane title set? | How |
|-------|----------------|-----|
| Claude Code (`claude`) | ✓ Yes | Sets `TERM_PROGRAM=claude`; pane title reflects the process |
| Cursor agent | Partial | Title may be `cursor` or the project name |
| Gemini CLI (`gemini`) | Partial | Title may be `gemini` or the shell |

If your agent's pane title doesn't include the agent name, set it manually in
your shell (add to `~/.zshrc` or `~/.bashrc`):

```bash
# Set tmux pane title to the current command
case "$TERM" in
  screen*|tmux*)
    # Called automatically by agents, or manually:
    printf '\033]2;claude\033\\'   # for Claude
    printf '\033]2;cursor\033\\'   # for Cursor
    printf '\033]2;gemini\033\\'   # for Gemini
    ;;
esac
```

Or use a shell hook to set the title automatically before each command:

```bash
# fish
function fish_title; basename (pwd); end

# zsh
precmd() { print -Pn "\e]2;%~\a"; }
preexec() { print -Pn "\e]2;$1\a"; }
```

---

## Customising the jump bindings

The default bindings are in `~/.config/tmux/tmux.conf`:

```tmux
bind a run-shell "tmux select-pane -t $(tmux list-panes -a -F '#{window_index}:#{pane_index} #{pane_title}' | grep -i 'claude\|claude-code' | head -1 | awk '{print $1}') 2>/dev/null || true"
bind g run-shell "tmux select-pane -t $(tmux list-panes -a -F '#{window_index}:#{pane_index} #{pane_title}' | grep -i 'gemini' | head -1 | awk '{print $1}') 2>/dev/null || true"
```

To add a Cursor binding:

```tmux
bind u run-shell "tmux select-pane -t $(tmux list-panes -a -F '#{window_index}:#{pane_index} #{pane_title}' | grep -i 'cursor' | head -1 | awk '{print $1}') 2>/dev/null || true"
```

Reload with `prefix + r`.

---

## Adding a new agent pattern

Edit `~/.config/tmux/scripts/agent-status.sh` and add a new block:

```bash
if echo "$pane_titles" | grep -qi 'codex\|openai-codex'; then
  out="${out}#[fg=colour46]⬢ Codex#[fg=colour244] "
fi
```

Reload the config (`prefix + r`) — the new indicator appears at the next poll.

---

## WSL2 notes

Pane-title propagation in WSL2 depends on the Windows terminal emulator you
use. Windows Terminal and Tabby pass pane titles correctly; other emulators may
not. If detection fails in WSL2, set the title manually with `printf '\033]2;claude\033\\'`
before starting your agent.

---

*fleetmux is a config, not an orchestrator. For multi-agent session management,
spawning, and monitoring from iOS, see [Termio](https://termio.xyz).*
