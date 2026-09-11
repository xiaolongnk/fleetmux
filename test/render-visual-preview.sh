#!/usr/bin/env bash
# Render a deterministic visual comparison when native screenshot access is unavailable.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT/.visual-preview}"
MAGICK="${MAGICK:-magick}"
FONT="${FLEETMUX_PREVIEW_FONT:-/System/Library/Fonts/Menlo.ttc}"
WALLPAPER="$ROOT/assets/ghostty/fleetmux-aurora.jpg"

command -v "$MAGICK" >/dev/null 2>&1 || { echo "ImageMagick is required" >&2; exit 1; }
[ -f "$FONT" ] || { echo "Set FLEETMUX_PREVIEW_FONT to a monospace font file" >&2; exit 1; }
mkdir -p "$OUT_DIR"

TEXT='fleetmux  fresh-install visual check

╭─ agent workspace ─────────────────────────────────────╮
│  branch   crew/fleetmux-visual-defaults                │
│  status   3 panes · 2 agents · tests passing           │
╰────────────────────────────────────────────────────────╯

✓ repeatability      PASS
✓ shell integration  zsh + zoxide
✓ visual preset      readable over real text

$ git status --short
 M bin/install.sh
?? assets/ghostty/

Tip: prefix + \\ splits side by side'

render_text() {
  local input="$1" output="$2" x="$3" y="$4" color="$5"
  "$MAGICK" "$input" -font "$FONT" -pointsize 12 -fill "$color" \
    -interline-spacing 3 -annotate "+${x}+${y}" "$TEXT" "$output"
}

# Shipped before-state: Ghostty defaults, two-pixel-equivalent inset, no theme or art.
"$MAGICK" -size 800x480 xc:'#282c34' "$OUT_DIR/before-base.png"
render_text "$OUT_DIR/before-base.png" "$OUT_DIR/before.png" 4 22 '#d8dee9'

# Proposed state over a deliberately bright desktop: theme + art at 18%, then 96% window opacity.
"$MAGICK" -size 800x480 xc:'#1e1e2e' \
  \( "$WALLPAPER" -resize '800x480^' -gravity center -extent 800x480 -alpha set -channel A -evaluate set 18% \) \
  -compose over -composite \
  \( +clone -alpha set -channel A -evaluate set 96% \) \
  -delete 0 -background '#f4f4f4' -compose over -flatten "$OUT_DIR/after-base.png"
render_text "$OUT_DIR/after-base.png" "$OUT_DIR/after.png" 12 28 '#cdd6f4'

"$MAGICK" "$OUT_DIR/before.png" "$OUT_DIR/after.png" +append "$OUT_DIR/before-after.png"
rm -f "$OUT_DIR/before-base.png" "$OUT_DIR/after-base.png"
printf 'VISUAL PREVIEW: wrote %s\n' "$OUT_DIR/before-after.png"
