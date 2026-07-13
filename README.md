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

**Requirements:** git (for TPM), curl. Nothing else — on macOS, if Homebrew itself
is missing, the installer bootstraps it for you (see below); tmux/starship/fish/
Ghostty are all installed through it. Debian/Ubuntu (`apt`) and Fedora (`dnf`)
use their native package manager instead — no Homebrew needed there.
WSL2: works — see [AGENTS.md](AGENTS.md#wsl2-notes) for pane-title caveats.
Windows native: not supported. Use WSL2.

**Homebrew bootstrap (macOS):** if `brew` isn't found, Step 0 runs Homebrew's own,
unmodified official installer (the same one at [brew.sh](https://brew.sh)) —
this may prompt for **your Mac password, in that terminal window**. fleetmux
never captures, scripts, or automates past that prompt; it's exactly the same
interactive install you'd get running Homebrew's installer yourself.

**Every component is detect-then-skip, never reinstalled without asking:**
tmux, Starship, and Fish are each checked against BOTH your `PATH` and their
common fixed install locations (not just `command -v`) before installing
anything — so a tmux from `apt`, a Starship from its own curl installer, or a
Fish you set up manually is correctly recognized as "already installed ✓" and
left alone, exactly like Ghostty's existing `/Applications/Ghostty.app` check.
Nothing is ever upgraded or reinstalled without an explicit re-run choosing to
do so. Running the installer twice in a row is a guaranteed no-op past the
first run — this is enforced by an automated CI test (`test/repeatability.sh`,
run.sh runs `install.sh` twice and diffs the resulting state + install-call
log) on every push.

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

**Change prefix (default is Ctrl-q):**
Edit the three lines near the top of `~/.config/tmux/tmux.conf`:
```tmux
unbind C-q
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

**My terminal looks frozen after `prefix + [`.** This is tmux's own
scrollback view ("copy mode"), not a hang — the status bar shows a
`📜 COPY MODE` banner while it's active. Press `q`, `Esc`, or `Ctrl-c` to get
back to your shell; nothing is lost. (A mouse-wheel scroll no longer
auto-enters copy mode — only the deliberate `prefix + [` does.)

---

## License

MIT — see [LICENSE](LICENSE).

---

📱 **Running Claude Code agents in tmux?** Monitor them from your iPhone with
**[Termio](https://termio.xyz)** — the mobile companion for AI agent workflows.
Watch pane output, send messages, and get notified when agents need you — from anywhere.
