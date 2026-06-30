#!/usr/bin/env bash
# fleetmux installer — agent-native tmux config for developers running AI agents.
# Working name: "fleetmux" (final name pending deeper clearance — see README).
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/xiaolongnk/fleetmux/main/bin/install.sh)
#
# What this does:
#   1. Detect OS (macOS/Linux/WSL2) and install tmux if missing
#   2. Install TPM (tmux plugin manager) if missing
#   3. Back up existing ~/.tmux.conf (if any)
#   4. Install config into ~/.config/tmux/tmux.conf + symlink ~/.tmux.conf
#   5. Install agent-status helper script
#   6. Install cheat sheet to ~/.config/tmux/CHEATSHEET.md
#   7. Remind the user to launch tmux and install plugins

set -euo pipefail

REPO_URL="${FLEETMUX_REPO_URL:-https://raw.githubusercontent.com/xiaolongnk/fleetmux/main}"
TMUX_CONF_DIR="$HOME/.config/tmux"
TMUX_CONF_FILE="$TMUX_CONF_DIR/tmux.conf"
TMUX_CONF_LINK="$HOME/.tmux.conf"
TPM_DIR="$HOME/.tmux/plugins/tpm"

# ── colors ───────────────────────────────────────────────────────────────────
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  C_GREEN=$(tput setaf 2); C_YELLOW=$(tput setaf 3); C_RED=$(tput setaf 1)
  C_BLUE=$(tput setaf 4); C_BOLD=$(tput bold); C_RESET=$(tput sgr0)
else
  C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""; C_BOLD=""; C_RESET=""
fi

ok()   { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
info() { printf '  %s•%s %s\n' "$C_BLUE"  "$C_RESET" "$*"; }
warn() { printf '  %s⚠%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
fail() { printf '\n  %s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
step() { printf '\n%s▸ %s%s\n' "$C_BOLD" "$*" "$C_RESET"; }

printf '\n  %sfleetmux installer%s — agent-native tmux config\n\n' "$C_BOLD" "$C_RESET"

# ── step 1: OS detect + tmux install ─────────────────────────────────────────
step "Step 1 — Detect OS and install tmux"

OS_KIND="$(uname -s)"
IN_WSL=false
if [ -f /proc/version ] && grep -qi 'microsoft\|wsl' /proc/version 2>/dev/null; then
  IN_WSL=true
fi

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
      warn "If pane titles don't show agent names, set them manually with: printf '\\033]2;claude\\033\\\\'"
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
        ubuntu|debian) _install_tmux_debian ;;
        fedora|rhel|centos) _install_tmux_fedora ;;
        *)
          warn "Unknown Linux distro '${LINUX_ID:-unknown}'. Install tmux with your package manager, then re-run."
          warn "Fedora/Arch: use your package manager for tmux (e.g. 'dnf install tmux' or 'pacman -S tmux')."
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

# Verify tmux ≥ 3.2
TMUX_VER_RAW="$(tmux -V 2>/dev/null | awk '{print $2}')"
TMUX_MAJOR="$(echo "$TMUX_VER_RAW" | cut -d. -f1 | tr -dc '0-9')"
TMUX_MINOR="$(echo "$TMUX_VER_RAW" | cut -d. -f2 | tr -dc '0-9')"
TMUX_MAJOR="${TMUX_MAJOR:-0}"; TMUX_MINOR="${TMUX_MINOR:-0}"
if [ "$TMUX_MAJOR" -lt 3 ] || { [ "$TMUX_MAJOR" -eq 3 ] && [ "$TMUX_MINOR" -lt 2 ]; }; then
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

# ── step 3: back up existing config ──────────────────────────────────────────
step "Step 3 — Backup existing config"
if [ -e "$TMUX_CONF_LINK" ] && [ ! -L "$TMUX_CONF_LINK" ]; then
  TS="$(date '+%Y%m%d%H%M%S')"
  mv "$TMUX_CONF_LINK" "${TMUX_CONF_LINK}.bak-${TS}"
  warn "Backed up $TMUX_CONF_LINK → ${TMUX_CONF_LINK}.bak-${TS}"
elif [ -e "$TMUX_CONF_FILE" ]; then
  TS="$(date '+%Y%m%d%H%M%S')"
  cp "$TMUX_CONF_FILE" "${TMUX_CONF_FILE}.bak-${TS}"
  warn "Backed up $TMUX_CONF_FILE → ${TMUX_CONF_FILE}.bak-${TS}"
else
  ok "No existing config to back up"
fi

# ── step 4: install config ────────────────────────────────────────────────────
step "Step 4 — Install config"
mkdir -p "$TMUX_CONF_DIR/scripts"

if ! curl -fsSL -o "$TMUX_CONF_FILE" "${REPO_URL}/tmux/tmux.conf" 2>/dev/null; then
  fail "Could not download tmux.conf from $REPO_URL. Check your internet connection."
fi

# Symlink ~/.tmux.conf → ~/.config/tmux/tmux.conf
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
    warn "Download manually: curl -fsSL ${REPO_URL}/tmux/scripts/$name > $dest && chmod +x $dest"
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

# ── step 7: done ─────────────────────────────────────────────────────────────
step "Done"
cat <<EOF

  ${C_GREEN}✅ fleetmux installed.${C_RESET}

  ${C_BOLD}Next steps:${C_RESET}
    1. Start (or restart) tmux:     ${C_BOLD}tmux${C_RESET}
    2. Install plugins:             ${C_BOLD}prefix + I${C_RESET}  (capital I)
       This downloads tmux-sensible, tmux-resurrect, tmux-continuum, tmux-yank.
    3. Open the cheat sheet:        ${C_BOLD}prefix + ?${C_RESET}
    4. Run an AI agent in a pane — status bar will detect it automatically.

  ${C_BOLD}Prefix key:${C_RESET} Ctrl-b  (default; see CHEATSHEET.md to change to Ctrl-a)

  ${C_BOLD}Upgrade anytime:${C_RESET}
    bash <(curl -fsSL ${REPO_URL}/bin/install.sh)

  📱  Running Claude Code agents in tmux? Monitor them from your iPhone with
      Termio — the mobile companion for AI agent workflows.
      ${C_BLUE}https://termio.xyz${C_RESET}

EOF
