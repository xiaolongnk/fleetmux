# Agent-Pane Detection

fleetmux's status bar and jump bindings work by probing the **command running in each
pane** of your tmux server. No daemon or background process is required.

---

## How detection works

Every 5 seconds, `agent-status.sh` runs inside tmux and executes:

```bash
tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}\t#{pane_current_command}\t#{pane_title}'
```

and classifies each pane by its **running command** (basename, case-insensitive,
`.exe` stripped):

| Command | Agent | Indicator |
|---------|-------|-----------|
| `claude`, `claude-code` | Claude Code | `⬡ Claude N` |
| `codex`, `codex-cli` | OpenAI Codex | `◆ Codex N` |
| `cursor-agent`, `cursor` | Cursor | `▣ Cursor N` |
| `gemini`, `gemini-cli` | Gemini CLI | `◈ Gemini N` |
| `node`, `bun`, `deno`, `python*`, `uv` | *generic runtime* — the pane **title** decides (contains `claude`/`codex`/`cursor`/`gemini`?) | as above |

`N` is the number of panes. Nothing running → nothing shown.

**Why the command, not the title.** Claude Code sets the pane title to the conversation
topic (`✳ Fix login bug`), Codex to the current task — on a real server with 12 Claude
and 16 Codex panes, only 1 title contained the word "claude" and none contained "codex".
The running command is unambiguous. Titles are consulted only for agents that run under
a generic runtime (Gemini CLI is a Node program, so its pane says `node`).

`agent-status.sh --list [agent]` prints one line per agent pane (`target  agent  title`);
`agent-jump.sh <agent|any>` uses it to cycle the jump bindings through every matching pane.

---

## When the title matters (generic-runtime agents)

If your agent runs under `node`/`python` and its pane title doesn't include the agent
name, set it in your shell (add to `~/.zshrc` or `~/.bashrc`):

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

The defaults in `~/.config/tmux/tmux.conf`:

```tmux
bind a   run-shell "~/.config/tmux/scripts/agent-jump.sh claude"
bind e   run-shell "~/.config/tmux/scripts/agent-jump.sh codex"
bind g   run-shell "~/.config/tmux/scripts/agent-jump.sh gemini"
bind Tab run-shell "~/.config/tmux/scripts/agent-jump.sh any"
```

Add your own in `~/.config/tmux/local.conf` (sourced by tmux.conf, kept across upgrades):

```tmux
bind u run-shell "~/.config/tmux/scripts/agent-jump.sh cursor"
```

Reload with `prefix + r`.

---

## Adding a new agent

Edit `classify()` in `~/.config/tmux/scripts/agent-status.sh` — one `case` arm per
command name — and add a counter + indicator line at the bottom:

```bash
    aider)                     echo aider;  return ;;
...
[ "$n_aider" -gt 0 ] && out="${out}#[fg=colour46]⬢ Aider ${n_aider}#[fg=colour244]  "
```

Reload the config (`prefix + r`) — the new indicator appears at the next poll.
`test/agent-status.sh` in the repo shows how to assert it against a fixture.

---

## WSL2 notes

Pane-title propagation in WSL2 depends on the Windows terminal emulator you
use. Windows Terminal and Tabby pass pane titles correctly; other emulators may
not. If detection fails in WSL2, set the title manually with `printf '\033]2;claude\033\\'`
before starting your agent.

---

*fleetmux is a config, not an orchestrator. For multi-agent session management,
spawning, and monitoring from iOS, see [Termio](https://termio.xyz).*
