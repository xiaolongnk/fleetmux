#!/usr/bin/env bash
# fleetmux installer — agent-native terminal environment for developers running AI agents.
# fleetmux-managed
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/xiaolongnk/fleetmux/main/bin/install.sh) [OPTIONS]
#
# Flags (v1):
#   --minimal         tmux + TPM only (skip Starship, Nerd Font)
#   --no-starship     Skip Starship prompt
#   --no-font         Skip Nerd Font
#   --yes, -y         Auto-confirm all prompts (CI / headless)
#
# Flags (v2 — coming soon, accepted but not yet active):
#   --with-fish       Opt in to Fish shell installation
#   --with-ghostty    Opt in to Ghostty terminal installation
#   --full            All components (tmux + starship + font + fish + ghostty)

set -euo pipefail

REPO_URL="${FLEETMUX_REPO_URL:-https://raw.githubusercontent.com/xiaolongnk/fleetmux/main}"
TMUX_CONF_DIR="$HOME/.config/tmux"
TMUX_CONF_FILE="$TMUX_CONF_DIR/tmux.conf"
TMUX_CONF_LINK="$HOME/.tmux.conf"
TPM_DIR="$HOME/.tmux/plugins/tpm"
STARSHIP_CONF="$HOME/.config/starship.toml"
LOCAL_BIN="$HOME/.local/bin"
FLEETMUX_SENTINEL="# fleetmux-managed"

# ── colors ───────────────────────────────────────────────────────────────────
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  C_GREEN=$(tput setaf 2); C_YELLOW=$(tput setaf 3); C_RED=$(tput setaf 1)
  C_BLUE=$(tput setaf 4); C_BOLD=$(tput bold); C_RESET=$(tput sgr0)
else
  C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""; C_BOLD=""; C_RESET=""
fi

ok()   { printf '  %s✓%s %s\n' "$C_GREEN"  "$C_RESET" "$*"; }
info() { printf '  %s•%s %s\n' "$C_BLUE"   "$C_RESET" "$*"; }
warn() { printf '  %s⚠%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
fail() { printf '\n  %s✗%s %s\n' "$C_RED"  "$C_RESET" "$*" >&2; exit 1; }
step() { printf '\n%s▸ %s%s\n' "$C_BOLD" "$*" "$C_RESET"; }
_ts()  { date '+%Y%m%d%H%M%S'; }

# ── helper: direct Nerd Font download (no brew) ───────────────────────────────
_install_font_direct() {
  local font_dir="$1"
  mkdir -p "$font_dir"
  local font_url="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.zip"
  local font_tmp
  font_tmp="$(mktemp -d)"
  info "Downloading JetBrains Mono Nerd Font…"
  if curl -fsSL -o "$font_tmp/JetBrainsMono.zip" "$font_url" 2>/dev/null \
     && command -v unzip >/dev/null 2>&1; then
    unzip -q -o "$font_tmp/JetBrainsMono.zip" "*.ttf" -d "$font_dir" 2>/dev/null || true
    rm -rf "$font_tmp"
    if [ "$(uname -s)" = "Linux" ]; then
      fc-cache -f "$font_dir" 2>/dev/null || true
    fi
    ok "JetBrains Mono Nerd Font installed to $font_dir"
  else
    warn "Font download failed. Install manually: https://www.nerdfonts.com/font-downloads"
    rm -rf "$font_tmp"
  fi
}

# ── flag parsing ──────────────────────────────────────────────────────────────
OPT_MINIMAL=false
OPT_NO_STARSHIP=false
OPT_NO_FONT=false
OPT_YES=false
OPT_WITH_FISH=false
OPT_WITH_GHOSTTY=false
OPT_FULL=false

for arg in "$@"; do
  case "$arg" in
    --minimal)      OPT_MINIMAL=true ;;
    --no-starship)  OPT_NO_STARSHIP=true ;;
    --no-font)      OPT_NO_FONT=true ;;
    --yes|-y)       OPT_YES=true ;;
    --with-fish)    OPT_WITH_FISH=true ;;
    --with-ghostty) OPT_WITH_GHOSTTY=true ;;
    --full)         OPT_FULL=true ;;
    *)              warn "Unknown flag: $arg (ignoring)" ;;
  esac
done

# v2 flag stubs — accept gracefully, print notice, continue with v1 profile
if $OPT_WITH_FISH || $OPT_WITH_GHOSTTY || $OPT_FULL; then
  printf '\n  %s• v2 flags detected — coming in fleetmux v2:%s\n' "$C_BLUE" "$C_RESET"
  # shellcheck disable=SC2016
  $OPT_WITH_FISH    && printf '     --with-fish    → Fish shell support (opt-in, changes $SHELL)\n'
  $OPT_WITH_GHOSTTY && printf '     --with-ghostty → Ghostty terminal support (macOS/Linux opt-in)\n'
  $OPT_FULL         && printf '     --full         → Full profile including fish + ghostty\n'
  printf '  Continuing with v1 profile: tmux + starship + nerd font.\n'
fi

IS_TTY=false
[ -t 0 ] && IS_TTY=true

printf '\n  %sfleetmux installer%s — agent-native terminal environment\n\n' "$C_BOLD" "$C_RESET"

# ── OS detect ─────────────────────────────────────────────────────────────────
OS_KIND="$(uname -s)"
IN_WSL=false
if [ -f /proc/version ] && grep -qi 'microsoft\|wsl' /proc/version 2>/dev/null; then
  IN_WSL=true
fi

# ── step 1: OS detect + tmux install ─────────────────────────────────────────
step "Step 1 — Detect OS and install tmux"

_install_tmux_macos() {
  if command -v brew >/dev/null 2>&1; then
    brew install tmux
  else
    fail "Homebrew is required to install tmux on macOS. Install from https://brew.sh then re-run."
  fi
}

_install_tmux_debian() {
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq && sudo apt-get install -y tmux
  else
    fail "apt-get not found. Install tmux manually: https://github.com/tmux/tmux/wiki"
  fi
}

_install_tmux_fedora() {
  if command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y tmux
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y tmux
  else
    fail "dnf/yum not found. Install tmux manually: https://github.com/tmux/tmux/wiki"
  fi
}

case "$OS_KIND" in
  Darwin)
    ok "macOS"
    if ! command -v tmux >/dev/null 2>&1; then
      info "Installing tmux via Homebrew…"
      _install_tmux_macos
    else
      ok "tmux already installed ($(tmux -V))"
    fi
    ;;
  Linux)
    if $IN_WSL; then
      warn "WSL2 detected. tmux works well in WSL2 but pane-title detection may differ from native Linux."
      warn "If pane titles don't show agent names, set them manually: printf '\\033]2;claude\\033\\\\'"
    else
      ok "Linux"
    fi
    if ! command -v tmux >/dev/null 2>&1; then
      info "Installing tmux…"
      LINUX_ID=""
      if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        LINUX_ID="${ID:-}"
      fi
      case "$LINUX_ID" in
        ubuntu|debian)      _install_tmux_debian ;;
        fedora|rhel|centos) _install_tmux_fedora ;;
        *)
          warn "Unknown Linux distro '${LINUX_ID:-unknown}'. Install tmux with your package manager, then re-run."
          fail "Cannot auto-install tmux on this distro."
          ;;
      esac
    else
      ok "tmux already installed ($(tmux -V))"
    fi
    ;;
  *)
    warn "Windows native is not supported. Use WSL2: https://learn.microsoft.com/en-us/windows/wsl/install"
    fail "Unsupported platform: $OS_KIND"
    ;;
esac

# Verify tmux version
TMUX_VER_RAW="$(tmux -V 2>/dev/null | awk '{print $2}')"
TMUX_MAJOR="$(echo "$TMUX_VER_RAW" | cut -d. -f1 | tr -dc '0-9')"
TMUX_MINOR="$(echo "$TMUX_VER_RAW" | cut -d. -f2 | tr -dc '0-9')"
TMUX_MAJOR="${TMUX_MAJOR:-0}"; TMUX_MINOR="${TMUX_MINOR:-0}"
if [ "$TMUX_MAJOR" -lt 3 ]; then
  fail "tmux $TMUX_VER_RAW is too old (minimum 3.0). Upgrade: brew upgrade tmux (macOS) or apt-get install tmux"
elif [ "$TMUX_MAJOR" -eq 3 ] && [ "$TMUX_MINOR" -lt 2 ]; then
  warn "tmux $TMUX_VER_RAW is below the recommended 3.2. Some features may not work."
  warn "Upgrade: brew upgrade tmux (macOS) or apt-get install tmux (Debian/Ubuntu)"
fi
ok "tmux $TMUX_VER_RAW"

# ── step 2: TPM ───────────────────────────────────────────────────────────────
step "Step 2 — TPM (tmux plugin manager)"
if [ -d "$TPM_DIR" ]; then
  ok "TPM already installed ($TPM_DIR)"
else
  info "Installing TPM via git clone…"
  if ! command -v git >/dev/null 2>&1; then
    fail "git is required to install TPM. Install git and re-run."
  fi
  git clone --depth=1 https://github.com/tmux-plugins/tpm "$TPM_DIR"
  ok "TPM installed to $TPM_DIR"
fi

# ── step 3: back up existing tmux config ─────────────────────────────────────
step "Step 3 — Backup existing tmux config"
if [ -e "$TMUX_CONF_LINK" ] && [ ! -L "$TMUX_CONF_LINK" ]; then
  TS="$(_ts)"
  mv "$TMUX_CONF_LINK" "${TMUX_CONF_LINK}.bak-${TS}"
  warn "Backed up $TMUX_CONF_LINK → ${TMUX_CONF_LINK}.bak-${TS}"
elif [ -f "$TMUX_CONF_FILE" ] && ! grep -q "$FLEETMUX_SENTINEL" "$TMUX_CONF_FILE" 2>/dev/null; then
  TS="$(_ts)"
  cp "$TMUX_CONF_FILE" "${TMUX_CONF_FILE}.bak-${TS}"
  warn "Backed up $TMUX_CONF_FILE → ${TMUX_CONF_FILE}.bak-${TS}"
else
  ok "No non-fleetmux tmux config to back up"
fi

# ── step 4: install tmux config ───────────────────────────────────────────────
step "Step 4 — Install tmux config"
mkdir -p "$TMUX_CONF_DIR/scripts"

if ! curl -fsSL -o "$TMUX_CONF_FILE" "${REPO_URL}/tmux/tmux.conf" 2>/dev/null; then
  fail "Could not download tmux.conf from $REPO_URL. Check your internet connection."
fi

if [ -L "$TMUX_CONF_LINK" ]; then
  rm "$TMUX_CONF_LINK"
fi
ln -sf "$TMUX_CONF_FILE" "$TMUX_CONF_LINK"
ok "Config installed: $TMUX_CONF_FILE"
ok "Symlinked: $TMUX_CONF_LINK → $TMUX_CONF_FILE"

# ── step 5: helper scripts ────────────────────────────────────────────────────
step "Step 5 — Helper scripts"
mkdir -p "$TMUX_CONF_DIR/scripts"

_install_script() {
  local name="$1"
  local dest="$TMUX_CONF_DIR/scripts/$name"
  if ! curl -fsSL -o "$dest" "${REPO_URL}/tmux/scripts/$name" 2>/dev/null; then
    warn "Could not download $name — some features may be unavailable."
    warn "Manual: curl -fsSL ${REPO_URL}/tmux/scripts/$name > $dest && chmod +x $dest"
  else
    chmod +x "$dest"
    ok "$name installed"
  fi
}

_install_script agent-status.sh
_install_script firstrun-popup.sh
_install_script firstrun-show.sh

# ── step 6: cheat sheet ──────────────────────────────────────────────────────
step "Step 6 — Cheat sheet"
CHEATSHEET_DEST="$TMUX_CONF_DIR/CHEATSHEET.md"
if ! curl -fsSL -o "$CHEATSHEET_DEST" "${REPO_URL}/CHEATSHEET.md" 2>/dev/null; then
  warn "Could not download CHEATSHEET.md — get it from ${REPO_URL}/CHEATSHEET.md"
else
  ok "Cheat sheet installed: $CHEATSHEET_DEST"
  ok "In-tmux: press prefix + ? to open the cheat sheet"
fi

# ── minimal profile: skip starship + font ─────────────────────────────────────
if $OPT_MINIMAL; then
  info "--minimal: skipping Starship and Nerd Font"
else

# ── step 7: Starship prompt ───────────────────────────────────────────────────
step "Step 7 — Starship prompt"
if $OPT_NO_STARSHIP; then
  info "--no-starship: skipping Starship"
else
  if command -v starship >/dev/null 2>&1; then
    ok "Starship already installed ($(starship --version 2>/dev/null | head -1))"
  else
    info "Installing Starship…"
    case "$OS_KIND" in
      Darwin)
        if command -v brew >/dev/null 2>&1; then
          brew install starship
        else
          curl -sS https://starship.rs/install.sh | sh -s -- --yes
        fi
        ;;
      Linux)
        curl -sS https://starship.rs/install.sh | sh -s -- --yes
        ;;
    esac
    ok "Starship installed ($(starship --version 2>/dev/null | head -1))"
  fi

  STARSHIP_CONF_PRESET=$(cat <<'TOML'
# fleetmux-managed — generated by fleetmux installer
# Customize at ~/.config/starship.toml — see https://starship.rs/config/

format = """
$username\
$hostname\
$directory\
$git_branch\
$git_status\
$nodejs\
$python\
$rust\
$golang\
$cmd_duration\
$line_break\
$character"""

[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"

[directory]
truncation_length = 4
truncate_to_repo = true
style = "bold blue"

[git_branch]
symbol = " "
format = "[$symbol$branch]($style) "
style = "bold purple"

[git_status]
format = '([\[$all_status$ahead_behind\]]($style) )'
style = "bold red"

[cmd_duration]
min_time = 2_000
format = "[⏱ $duration]($style) "
style = "yellow"

[nodejs]
symbol = " "
format = "[$symbol($version )]($style)"

[python]
symbol = " "
format = '[$symbol${pyenv_prefix}(${version} )(\($virtualenv\) )]($style)'

[rust]
symbol = " "
format = "[$symbol($version )]($style)"

[golang]
symbol = " "
format = "[$symbol($version )]($style)"
TOML
)

  mkdir -p "$(dirname "$STARSHIP_CONF")"
  if [ -f "$STARSHIP_CONF" ]; then
    if grep -q "$FLEETMUX_SENTINEL" "$STARSHIP_CONF" 2>/dev/null; then
      printf '%s\n' "$STARSHIP_CONF_PRESET" > "$STARSHIP_CONF"
      ok "Starship config updated (fleetmux-managed): $STARSHIP_CONF"
    else
      TS="$(_ts)"
      cp "$STARSHIP_CONF" "${STARSHIP_CONF}.bak-${TS}"
      warn "Backed up existing $STARSHIP_CONF → ${STARSHIP_CONF}.bak-${TS}"
      if $OPT_YES; then
        printf '%s\n' "$STARSHIP_CONF_PRESET" > "$STARSHIP_CONF"
        ok "Starship config installed (--yes, overwrote): $STARSHIP_CONF"
      elif $IS_TTY; then
        printf '\n  %s⚠  ~/.config/starship.toml already exists. Choose:%s\n' "$C_YELLOW" "$C_RESET"
        printf '    [O] Overwrite with fleetmux preset  (backup: %s.bak-%s)\n' "$STARSHIP_CONF" "$TS"
        printf '    [K] Keep yours  (fleetmux preset saved as starship.toml.fleetmux)\n'
        printf '    [S] Skip starship configuration entirely\n'
        printf '  Choice [O/K/S]: '
        read -r STARSHIP_CHOICE
        case "${STARSHIP_CHOICE:-S}" in
          [Oo])
            printf '%s\n' "$STARSHIP_CONF_PRESET" > "$STARSHIP_CONF"
            ok "Starship config installed: $STARSHIP_CONF"
            ;;
          [Kk])
            printf '%s\n' "$STARSHIP_CONF_PRESET" > "${STARSHIP_CONF}.fleetmux"
            ok "fleetmux preset saved as ${STARSHIP_CONF}.fleetmux (your config unchanged)"
            ;;
          *)
            info "Skipping Starship config installation"
            ;;
        esac
      else
        printf '%s\n' "$STARSHIP_CONF_PRESET" > "${STARSHIP_CONF}.fleetmux"
        info "Non-interactive: kept your starship.toml; fleetmux preset at ${STARSHIP_CONF}.fleetmux"
      fi
    fi
  else
    printf '%s\n' "$STARSHIP_CONF_PRESET" > "$STARSHIP_CONF"
    ok "Starship config created: $STARSHIP_CONF"
  fi

  # Add starship init line to shell RC (non-destructive: only if absent)
  _add_starship_init() {
    local rc_file="$1" init_line="$2"
    if [ -f "$rc_file" ]; then
      if grep -qF "starship init" "$rc_file" 2>/dev/null; then
        ok "Starship init already in $rc_file"
      else
        printf '\n%s\n%s\n' "$FLEETMUX_SENTINEL" "$init_line" >> "$rc_file"
        ok "Added starship init to $rc_file"
      fi
    fi
  }

  CURRENT_SHELL="$(basename "${SHELL:-bash}")"
  # shellcheck disable=SC2016
  case "$CURRENT_SHELL" in
    bash) _add_starship_init "$HOME/.bashrc" 'eval "$(starship init bash)"' ;;
    zsh)  _add_starship_init "$HOME/.zshrc"  'eval "$(starship init zsh)"' ;;
    fish) info "Fish shell: add 'starship init fish | source' to ~/.config/fish/config.fish" ;;
    *)    info "Add starship init for your shell: https://starship.rs/guide/#step-2" ;;
  esac
fi # end: ! $OPT_NO_STARSHIP

# ── step 8: Nerd Font ─────────────────────────────────────────────────────────
step "Step 8 — Nerd Font (JetBrains Mono Nerd)"
if $OPT_NO_FONT; then
  info "--no-font: skipping Nerd Font"
else
  _nerd_font_detected() {
    if fc-list 2>/dev/null | grep -qi "nerd"; then
      return 0
    fi
    if [ "$OS_KIND" = "Darwin" ] && find "$HOME/Library/Fonts" -iname "*nerd*" 2>/dev/null | grep -q .; then
      return 0
    fi
    return 1
  }

  if _nerd_font_detected; then
    ok "Nerd Font already detected — skipping font install"
  else
    case "$OS_KIND" in
      Darwin)
        if command -v brew >/dev/null 2>&1; then
          info "Installing JetBrains Mono Nerd Font via Homebrew…"
          if brew install --cask font-jetbrains-mono-nerd-font 2>/dev/null; then
            ok "JetBrains Mono Nerd Font installed"
          else
            warn "Cask install failed — trying direct download…"
            _install_font_direct "$HOME/Library/Fonts"
          fi
        else
          _install_font_direct "$HOME/Library/Fonts"
        fi
        ;;
      Linux)
        _install_font_direct "$HOME/.local/share/fonts"
        ;;
    esac
    warn "Set 'JetBrains Mono Nerd Font' in your terminal preferences so Starship icons render."
  fi
fi # end: ! $OPT_NO_FONT

fi # end: ! $OPT_MINIMAL

# ── step 9: install fleetmux-start on PATH ────────────────────────────────────
step "Step 9 — Install fleetmux-start"
mkdir -p "$LOCAL_BIN"
FMUX_START_DEST="$LOCAL_BIN/fleetmux-start"

if ! curl -fsSL -o "$FMUX_START_DEST" "${REPO_URL}/bin/start" 2>/dev/null; then
  warn "Could not download bin/start — fleetmux-start not installed."
  warn "Manual: curl -fsSL ${REPO_URL}/bin/start > $FMUX_START_DEST && chmod +x $FMUX_START_DEST"
else
  chmod +x "$FMUX_START_DEST"
  ok "fleetmux-start installed: $FMUX_START_DEST"
fi

if ! printf '%s' "$PATH" | tr ':' '\n' | grep -qxF "$LOCAL_BIN" 2>/dev/null; then
  warn "$HOME/.local/bin is not on your PATH. Add to your shell RC:"
  warn "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# ── step 10: done ─────────────────────────────────────────────────────────────
step "Done"
printf '\n  %s✅ fleetmux installed.%s\n\n' "$C_GREEN" "$C_RESET"
printf '  %sWhat was installed:%s\n' "$C_BOLD" "$C_RESET"
printf '    • tmux config + TPM              %s\n' "$TMUX_CONF_FILE"
if ! $OPT_MINIMAL && ! $OPT_NO_STARSHIP; then
  printf '    • Starship prompt                %s\n' "$STARSHIP_CONF"
fi
if ! $OPT_MINIMAL && ! $OPT_NO_FONT; then
  printf '    • JetBrains Mono Nerd Font\n'
fi
printf '    • fleetmux-start                 %s\n' "$FMUX_START_DEST"

cat <<EOF

  ${C_BOLD}Next steps:${C_RESET}
    1. Start (or restart) tmux:       ${C_BOLD}tmux${C_RESET}  or  ${C_BOLD}fleetmux-start${C_RESET}
    2. Install plugins:               ${C_BOLD}prefix + I${C_RESET}  (capital I)
       Downloads tmux-sensible, tmux-resurrect, tmux-continuum, tmux-yank.
    3. Open the cheat sheet:          ${C_BOLD}prefix + ?${C_RESET}
    4. Run an AI agent in a pane — status bar detects it automatically.

  ${C_BOLD}Prefix key:${C_RESET} Ctrl-b  (default — see CHEATSHEET.md to switch to Ctrl-a)

  ${C_BOLD}Upgrade anytime:${C_RESET}
    bash <(curl -fsSL ${REPO_URL}/bin/install.sh)

EOF

if [ -n "${TMUX:-}" ]; then
  printf '  %s✓%s  agent-status.sh is live. Pane states show in the status bar.\n' "$C_GREEN" "$C_RESET"
  printf '     📱  See them on your iPhone → %shttps://termio.xyz%s\n\n' "$C_BLUE" "$C_RESET"
else
  printf '  📱  Running Claude Code agents in tmux? Monitor them from your iPhone with\n'
  printf '      Termio — the mobile companion for AI agent workflows.\n'
  printf '      %shttps://termio.xyz%s\n\n' "$C_BLUE" "$C_RESET"
fi
