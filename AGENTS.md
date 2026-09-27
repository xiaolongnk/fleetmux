# Agent-Pane Detection

fleetmux's status bar and jump bindings work by probing the **command running in each
pane** of your tmux server. No daemon or background process is required.

Both come from one TPM plugin, [tmux-agent-status](https://github.com/xiaolongnk/tmux-agent-status)
(`~/.tmux/plugins/tmux-agent-status`, cloned by the installer next to TPM). `tmux.conf`
declares it with `set -g @plugin 'xiaolongnk/tmux-agent-status'` and leaves a
`#{agent_status}` placeholder in `status-right`; at TPM init the plugin swaps the placeholder
for its probe and binds the jump keys. fleetmux ships no copy of the scripts itself — the
paths below are inside the plugin directory.

---

## How detection works

Every 5 seconds, the plugin's `scripts/agent-status.sh` runs inside tmux and executes:

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

### State: busy, attention, idle

tmux has no per-pane activity clock, but every agent prints the same tells on its screen, so
`agent-status.sh` reads the last 8 lines of each agent pane (`tmux capture-pane`):

| Screen contains | State | Meaning |
|---|---|---|
| `esc to interrupt` / `esc to cancel` / a braille spinner `⠇` | **busy** | still working — leave it |
| `Do you want to proceed`, `❯ 1. Yes`, `(y/n)`, `Allow`, `Approve` | **attention** | asking for approval |
| neither | **idle** | finished, waiting for your next message |

The status bar shows attention + idle as an amber `●N` after the agent's count; `prefix + Enter`
(`agent-jump.sh waiting`) cycles through exactly those panes. `agent-status.sh --list` prints
the state per pane if you want to script on it.

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

The keys are plugin options, read when TPM initialises the plugin. The defaults:

| Option | Default | Cycles |
|---|---|---|
| `@agent_status_jump_waiting` | `Enter` | agent panes waiting for you (idle or approval prompt) |
| `@agent_status_jump_any` | `Tab` | every agent pane |
| `@agent_status_jump_claude` | `a` | Claude Code panes |
| `@agent_status_jump_codex` | `e` | Codex panes |
| `@agent_status_jump_gemini` | `g` | Gemini panes |
| `@agent_status_jump_cursor` | *(unbound)* | Cursor panes |

Override them in `~/.config/tmux/local.conf` (sourced by tmux.conf **before** TPM runs, kept
across upgrades). `''` leaves a key alone:

```tmux
set -g @agent_status_jump_cursor 'u'     # prefix + u → next Cursor pane
set -g @agent_status_jump_gemini ''      # keep prefix + g for something else
```

Reload with `prefix + r`. Anything else the plugin's script can do is one `run-shell` away,
e.g. `bind M-Enter run-shell "~/.tmux/plugins/tmux-agent-status/scripts/agent-jump.sh waiting"`.

---

## Adding a new agent

The detection table lives in the plugin: edit `classify()` in
`~/.tmux/plugins/tmux-agent-status/scripts/agent-status.sh` — one `case` arm per command
name — and add a counter + indicator line at the bottom:

```bash
    aider)                     echo aider;  return ;;
...
[ "$n_aider" -gt 0 ] && out="${out}#[fg=colour46]⬢ Aider ${n_aider}#[fg=colour244]  "
```

Reload the config (`prefix + r`) — the new indicator appears at the next poll. Note that
`prefix + U` (TPM update) will overwrite a local edit, so send it upstream: the plugin's
`test/agent-status.sh` shows how to assert a new agent against a fixture, and a merged
change reaches every fleetmux install on its next `prefix + U`.

---

## WSL2 notes

Pane-title propagation in WSL2 depends on the Windows terminal emulator you
use. Windows Terminal and Tabby pass pane titles correctly; other emulators may
not. If detection fails in WSL2, set the title manually with `printf '\033]2;claude\033\\'`
before starting your agent.

---

## Upgrading from a pre-1.3 install

Earlier installers downloaded `agent-status.sh` and `agent-jump.sh` into
`~/.config/tmux/scripts/` and hard-wired the jump keys in `tmux.conf`. Re-running the
installer removes those copies and writes the plugin-based config; `fleetmux-doctor` warns
if a stale copy is still around. Local edits to the old scripts are not migrated — redo them
in the plugin (see above).

---

*fleetmux is a config, not an orchestrator. For multi-agent session management,
spawning, and monitoring from iOS, see [Termio](https://termio.xyz).*
