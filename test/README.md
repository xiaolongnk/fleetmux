# Tests

| File | What it proves | Where it runs |
|---|---|---|
| `agent-status.sh` | The agent probe classifies real-world pane shapes correctly (Claude Code titles are topics, not "claude"; Codex is detected; Gemini under `node` is found by title; a shell pane is not an agent). Feeds fixtures through `FLEETMUX_PANES`. | CI, every push |
| `repeatability.sh` | Running `install.sh` twice converges: identical file list + content, zero `brew install` / `git clone` on run 2. Uses a scratch `HOME` and `FLEETMUX_REPO_URL=file://…`. | CI (macOS), every push |
| `visual/` | Renders the shipped tmux config in an isolated Ghostty and captures the window, for eyeballing/measuring theme changes. | by hand, macOS only |

## Visual regression harness (macOS)

Render any Ghostty config against a fixed fleetmux tmux fixture and capture the
specific Ghostty window (not whichever screen happens to be frontmost):

```bash
test/visual/render-ghostty.sh \
  --config-file test/visual/configs/current.conf \
  --output /tmp/fleetmux-current.png
```

The harness requires Ghostty, tmux, Swift, and ImageMagick (`magick`). It launches
Ghostty with scratch `HOME` and `XDG_CONFIG_HOME` directories, plus the CLI-only
`config-default-files=false`, so the operator's personal config cannot leak into
captures. It records the isolated process, selects one terminal-sized
CoreGraphics window owned by that process, and captures that id with
ScreenCaptureKit. Apple Vision OCR must then find the fixture sentinel in the
captured pixels, so a Ghostty dialog or settings window cannot pass. It crops the
macOS title bar and rejects empty or near-black output. The fixture starts an
isolated tmux server with the shipped `tmux/tmux.conf`; tmux itself draws the two
panes, active and inactive borders, window list, session name, status bar, and
agent indicator. The pane output and volatile status fields (time and hostname)
are fixed public fixture values, so repeated captures are comparable and cannot
leak machine state. Pass `--tmux-config-file` to compare another tmux config.
`test/visual/configs/contrast.conf` is an intentionally different
theme/opacity/padding fixture for proving that config changes reach the image.
`test/visual/measure-pane-border.py <capture.png>` locates the real divider and
reports active/inactive contrast from its rendered RGB pixels.

This is a local macOS/Ghostty visual tool, not a headless CI test. It requires a
logged-in GUI session, an awake display, Screen Recording permission, and does
not represent Linux terminals, WSL, Windows, or other terminal emulators.
