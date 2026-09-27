# fleetmux — Key Binding Cheat Sheet

> **Prefix key:** `Ctrl-q` (default)
> To change it, edit the three `prefix` lines near the top of `~/.config/tmux/tmux.conf`.

---

## Sessions

| Key | Action |
|-----|--------|
| `prefix + d` | Detach from session (session keeps running) |
| `prefix + $` | Rename current session |
| `prefix + s` | List / switch sessions |
| `tmux ls` | List all sessions (shell) |
| `tmux attach -t NAME` | Attach to a session by name (shell) |

## Windows (tabs)

| Key | Action |
|-----|--------|
| `prefix + c` | New window (opens in current path) |
| `prefix + n` | Next window |
| `prefix + p` | Previous window |
| `prefix + NUMBER` | Switch to window by number |
| `prefix + ,` | Rename current window |
| `prefix + &` | Close current window |

## Panes (splits)

| Key | Action |
|-----|--------|
| `prefix + \\` | Split vertically (side by side) |
| `prefix + -` | Split horizontally (top/bottom) |
| `prefix + h/j/k/l` | Navigate panes (vim-style: left/down/up/right) |
| `prefix + z` | Zoom / un-zoom current pane |
| `prefix + x` | Close current pane |
| `prefix + {` / `prefix + }` | Swap pane left / right |

## Agent-pane jumps

Each press goes to the NEXT pane running that agent (wraps around), across windows and sessions.

| Key | Action |
|-----|--------|
| `prefix + Enter` | Next agent that is **waiting for you** (idle or asking for approval) |
| `prefix + Tab` | Cycle through every agent pane |
| `prefix + a` | Cycle Claude Code panes |
| `prefix + e` | Cycle Codex panes |
| `prefix + g` | Cycle Gemini panes |

> These keys come from the `tmux-agent-status` plugin. Add one for Cursor with
> `set -g @agent_status_jump_cursor 'u'` in `~/.config/tmux/local.conf`; set an option to `''`
> (e.g. `@agent_status_jump_gemini`) to leave that key alone.

## Copy mode

`mouse on` means a wheel-scroll ALSO enters copy mode automatically (not just
`prefix + [`), so a scroll that "froze" your terminal is just this, not a hang.

| Key | Action |
|-----|--------|
| `prefix + [` | Enter copy mode (scroll with arrows or vim keys) |
| `q` / `Esc` / `Ctrl-c` | Exit copy mode — any of the three works |
| `Space` | Start selection |
| `Enter` | Copy selection (tmux-yank also copies to system clipboard) |

## Config

| Key | Action |
|-----|--------|
| `prefix + r` | Reload config (`~/.config/tmux/tmux.conf`) |
| `prefix + ?` | Open this cheat sheet |
| `prefix + I` | Install / update plugins (capital I, via TPM) |
| `prefix + U` | Update plugins |
| `prefix + alt-u` | Uninstall unlisted plugins |

## Plugins installed

| Plugin | What it does |
|--------|-------------|
| `tmux-agent-status` | Agent counts + ● waiting marker in the status bar, and the jump keys above |
| `tmux-sensible` | Sane defaults everyone agrees on |
| `tmux-resurrect` | Save and restore sessions across reboots |
| `tmux-continuum` | Auto-save sessions every 15 min (restore on start) |
| `tmux-yank` | Copy to system clipboard in copy mode |

---

## Quick recipes

**Launch your agents, already running, one window each:**
```bash
fleetmux-start claude codex          # session "agents": claude | codex | shell
fleetmux-start -l claude claude      # -l: side by side in one window
fleetmux-start -s work gemini        # named session
```

**Check the status bar:**
The bottom of your terminal counts the panes running each agent, and how many of them are
waiting for you: `⬡ Claude 2 ●1  ◆ Codex 1` = two Claude panes, one of them idle or asking
for approval. Detected from the pane's running command and its screen — no title tricks.
Empty means no agent is running. `prefix + Enter` takes you to the next ● pane. Raw view:
`~/.tmux/plugins/tmux-agent-status/scripts/agent-status.sh --list`.

**Something looks wrong on a new machine:**
```bash
fleetmux-doctor
```
Checks config, plugins, pane shell, fish preset, agent CLIs on PATH, font, and live
detection; every ✗ line says what to do.

---

*In-tmux: open with `prefix + ?` · Online: https://github.com/xiaolongnk/fleetmux*
