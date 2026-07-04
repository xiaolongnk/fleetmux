# fleetmux

**The agent-native tmux distribution.** A complete, opinionated tmux setup for developers
running AI coding agents. One command. Looks great out of the box. Status bar surfaces
agent pane states automatically.

```
┌─────────────────────────────────────────────────────────┐
│  claude  shell                                          │
│                                                         │
│  > claude                                               │
│  ✻ Thinking…                                            │
│                                                         │
│                                                         │
│ agents  ⬡ Claude  14:02  hostname                       │
└─────────────────────────────────────────────────────────┘
```

---

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/xiaolongnk/fleetmux/main/bin/install.sh)
```

Then start tmux and press `prefix + I` to install plugins, or use `fleetmux-start` to launch a pre-configured session.

**Requirements:** tmux ≥ 3.2, git (for TPM), curl.
The installer auto-installs tmux on macOS (Homebrew), Debian/Ubuntu (`apt`), and Fedora (`dnf`).
WSL2: works — see [AGENTS.md](AGENTS.md#wsl2-notes) for pane-title caveats.
Windows native: not supported. Use WSL2.

---

## What's included

| Component | What it does |
|-----------|-------------|
| `tmux/tmux.conf` | Full config: TPM, 4 plugins, agent-aware status bar, keybindings |
| `tmux/scripts/agent-status.sh` | Probes pane titles for Claude/Cursor/Gemini; drives the status bar |
| `bin/install.sh` | Idempotent installer: backs up config, installs TPM, Starship, Nerd Font, links config |
| `bin/start` | Launches a named session with Claude + Shell windows — installed as `fleetmux-start` |
| `CHEATSHEET.md` | Full key-binding reference (also accessible via `prefix + ?`) |
| `AGENTS.md` | How pane-title detection works and how to customize it |

### Plugins (via TPM)

| Plugin | Purpose |
|--------|---------|
| `tmux-sensible` | Sane defaults: UTF-8, fast escape, 256color |
| `tmux-resurrect` | Save + restore sessions across reboots |
| `tmux-continuum` | Auto-save every 15 minutes; restore on startup |
| `tmux-yank` | Copy to system clipboard in copy mode |

---

## Key bindings (highlights)

| Key | Action |
|-----|--------|
| `prefix + \|` | Split pane vertically |
| `prefix + -` | Split pane horizontally |
| `prefix + h/j/k/l` | Navigate panes |
| `prefix + a` | Jump to Claude Code pane |
| `prefix + g` | Jump to Gemini pane |
| `prefix + r` | Reload config |
| `prefix + ?` | Open cheat sheet |
| `prefix + I` | Install / update plugins |

See [CHEATSHEET.md](CHEATSHEET.md) for the full reference.

---

## What this is NOT

- **Not a session manager.** tmuxinator / tmuxifier fill that lane; they compose well with fleetmux.
- **Not a plugin manager.** We build on TPM, not replace it.
- **Not another pretty-config-only project.** Agent-aware status bar is the differentiation.
- **Not tied to Termio.** Genuinely useful standalone — the Termio mention is a footer, not a dependency.

---

## Configuration

Config lives at `~/.config/tmux/tmux.conf` (XDG-compliant); `~/.tmux.conf` is symlinked to it.

**Change prefix to Ctrl-a:**
Uncomment the three lines near the top of `~/.config/tmux/tmux.conf`:
```tmux
unbind C-b
set -g prefix C-a
bind C-a send-prefix
```
Then reload: `prefix + r`.

**Add a custom agent indicator:**
Edit `~/.config/tmux/scripts/agent-status.sh` — see [AGENTS.md](AGENTS.md).

---

## Upgrade

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/xiaolongnk/fleetmux/main/bin/install.sh)
```

The installer backs up your existing config before replacing it.

---

## Uninstall

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/xiaolongnk/fleetmux/main/bin/install.sh) --uninstall
```

Removes everything fleetmux wrote — the config it manages (detected via its own
`# fleetmux-managed` marker, so a config you wrote yourself at the same path is
never touched), TPM, `fleetmux-start`, and the init lines it appended to your
shell RC. It does **not** uninstall the tmux/starship/fish/ghostty *binaries*
(you may still want them for other things) and does not revert `chsh` — both
are printed as explicit one-line commands for you to run instead of guessed at
automatically. Timestamped `*.bak-*` backups from earlier installs are left in
place; the command prints how many it found.

---

## Troubleshooting

**My terminal looks frozen after scrolling with the mouse.** This is tmux's
own scrollback view ("copy mode") — expected behavior when `mouse on` is set,
not a hang. The status bar shows a `📜 COPY MODE` banner while it's active.
Press `q`, `Esc`, or `Ctrl-c` to get back to your shell; nothing is lost.

---

## License

MIT — see [LICENSE](LICENSE).

---

📱 **Running Claude Code agents in tmux?** Monitor them from your iPhone with
**[Termio](https://termio.xyz)** — the mobile companion for AI agent workflows.
Watch pane output, send messages, and get notified when agents need you — from anywhere.
