# fleetmux — Key Binding Cheat Sheet

> **Prefix key:** `Ctrl-b` (default)
> To use `Ctrl-a` instead, uncomment the three lines in `~/.config/tmux/tmux.conf`.

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
| `prefix + \|` | Split vertically (side by side) |
| `prefix + -` | Split horizontally (top/bottom) |
| `prefix + h/j/k/l` | Navigate panes (vim-style: left/down/up/right) |
| `prefix + z` | Zoom / un-zoom current pane |
| `prefix + x` | Close current pane |
| `prefix + {` / `prefix + }` | Swap pane left / right |

## Agent-pane jumps

| Key | Action |
|-----|--------|
| `prefix + a` | Jump to first Claude Code pane |
| `prefix + g` | Jump to first Gemini pane |

> Cursor pane binding: add `bind u run-shell "tmux select-pane -t ..."` to
> `~/.config/tmux/tmux.conf` (see AGENTS.md for the full pattern).

## Copy mode

Enter copy mode deliberately with `prefix + [` — a stray mouse-wheel scroll
does NOT auto-enter it. The status bar shows a `📜 COPY MODE` banner while
it's active.

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
| `tmux-sensible` | Sane defaults everyone agrees on |
| `tmux-resurrect` | Save and restore sessions across reboots |
| `tmux-continuum` | Auto-save sessions every 15 min (restore on start) |
| `tmux-yank` | Copy to system clipboard in copy mode |

---

## Quick recipes

**Start a new agent session:**
```bash
tmux new-session -s work
# or use the bundled helper (run from the cloned repo):
bash bin/start
```

**Run Claude Code in a pane:**
```bash
claude
```

**Check the status bar:**
The bottom of your terminal shows detected agent panes (⬡ Claude, ▣ Cursor, ◈ Gemini).
If no agents appear in the bar, ensure your pane title includes the agent name.
Set pane title manually: `printf '\033]2;claude\033\\'`

---

*In-tmux: open with `prefix + ?` · Online: https://github.com/xiaolongnk/fleetmux*
