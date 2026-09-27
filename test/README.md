# Tests

| File | What it proves | Where it runs |
|---|---|---|
| `plugin-consumed.sh` | The status bar and jump keys come from the `tmux-agent-status` TPM plugin and from nowhere else: the repo ships no `agent-status.sh` / `agent-jump.sh` copies, `tmux.conf` declares the plugin and carries the `#{agent_status}` placeholder instead of hand-written binds, `install.sh` clones the plugin next to TPM and deletes pre-1.3 script copies on upgrade, `doctor` checks the plugin. With tmux present it also starts a server from the installed config and asserts the placeholder was substituted and `prefix + Enter` is bound. Sandboxed like `repeatability.sh`. | CI, every push |
| `repeatability.sh` | Running `install.sh` twice converges: identical file list + content, zero `brew install` / `git clone` on run 2. Uses a scratch `HOME` and `FLEETMUX_REPO_URL=file://…`. | CI (macOS), every push |
| `fish-preset.sh` | `install.sh --with-fish` in a clean box: fish preset, pinned pane shell, `--uninstall` removes both. | CI (macOS), every push |
| `visual/` | Renders the shipped tmux config in an isolated Ghostty and captures the window, for eyeballing/measuring theme changes. | by hand, macOS only |

The agent detection unit test (`FLEETMUX_PANES` fixtures through `agent-status.sh`) moved with
the code to the [tmux-agent-status](https://github.com/xiaolongnk/tmux-agent-status) repo.

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
