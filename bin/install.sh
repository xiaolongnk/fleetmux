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
# Flags (v2 — opt-in, high-invasiveness components):
#   --with-fish       Opt in to Fish shell installation (changes login shell via chsh)
#   --with-ghostty    Opt in to Ghostty terminal installation
#   --full            All components (tmux + starship + font + fish + ghostty)
#
# Flags (v2.1 — removal):
#   --uninstall       Remove everything fleetmux installed/wrote (see below).
#                      Never touches your Homebrew/apt-installed BINARIES
#                      (tmux/starship/fish/ghostty stay — uninstalling a
#                      terminal multiplexer a user may depend on for OTHER
#                      sessions is not this flag's call to make); removes only
#                      what fleetmux itself wrote: the config symlink/files it
#                      manages (detected via the `# fleetmux-managed` sentinel
#                      — never a file without it), TPM, fleetmux-start, and
#                      the shell-RC init lines it appended. Timestamped
#                      `.bak-*` backups from earlier runs are left in place
#                      and printed so you can restore your PRE-fleetmux config
#                      by hand. Does NOT revert `chsh` — printed instead as an
#                      explicit one-line command, since guessing your prior
#                      shell is unsafe to automate.

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
OPT_UNINSTALL=false

for arg in "$@"; do
  case "$arg" in
    --minimal)      OPT_MINIMAL=true ;;
    --no-starship)  OPT_NO_STARSHIP=true ;;
    --no-font)      OPT_NO_FONT=true ;;
    --yes|-y)       OPT_YES=true ;;
    --with-fish)    OPT_WITH_FISH=true ;;
    --with-ghostty) OPT_WITH_GHOSTTY=true ;;
    --full)         OPT_FULL=true ;;
    --uninstall)    OPT_UNINSTALL=true ;;
    *)              warn "Unknown flag: $arg (ignoring)" ;;
  esac
done

if $OPT_FULL; then
  OPT_WITH_FISH=true
  OPT_WITH_GHOSTTY=true
fi

IS_TTY=false
[ -t 0 ] && IS_TTY=true

printf '\n  %sfleetmux installer%s — agent-native terminal environment\n\n' "$C_BOLD" "$C_RESET"

# ── uninstall path (v2.1) — exits, never falls through to install steps ──────
if $OPT_UNINSTALL; then
  step "Removing fleetmux"

  # tmux config: the SENTINEL in the target file is the sole authority for
  # "is this ours" — matches install.sh's own backup logic above (step 3),
  # which also gates on the sentinel, not the symlink shape. A user who
  # independently symlinked ~/.tmux.conf -> ~/.config/tmux/tmux.conf as their
  # OWN convention (same path fleetmux happens to use) must keep BOTH the
  # symlink and the file — matching on symlink-target-path alone (without the
  # sentinel check) would delete a live shortcut to a file we correctly leave
  # untouched, orphaning the user's config from their expected path.
  TMUX_CONF_IS_OURS=false
  if [ -f "$TMUX_CONF_FILE" ] && grep -qF "$FLEETMUX_SENTINEL" "$TMUX_CONF_FILE" 2>/dev/null; then
    TMUX_CONF_IS_OURS=true
  fi
  if $TMUX_CONF_IS_OURS && [ -L "$TMUX_CONF_LINK" ] && [ "$(readlink "$TMUX_CONF_LINK")" = "$TMUX_CONF_FILE" ]; then
    rm "$TMUX_CONF_LINK"
    ok "Removed symlink: $TMUX_CONF_LINK"
  else
    info "$TMUX_CONF_LINK is not fleetmux's symlink — left alone"
  fi
  if $TMUX_CONF_IS_OURS; then
    rm "$TMUX_CONF_FILE"
    ok "Removed: $TMUX_CONF_FILE"
  fi
  if [ -f "$TMUX_CONF_DIR/scripts/agent-status.sh" ] || [ -f "$TMUX_CONF_DIR/scripts/firstrun-popup.sh" ] || [ -f "$TMUX_CONF_DIR/scripts/firstrun-show.sh" ]; then
    rm -f "$TMUX_CONF_DIR/scripts/agent-status.sh" "$TMUX_CONF_DIR/scripts/firstrun-popup.sh" "$TMUX_CONF_DIR/scripts/firstrun-show.sh"
    ok "Removed fleetmux helper scripts from $TMUX_CONF_DIR/scripts"
  fi
  [ -f "$TMUX_CONF_DIR/CHEATSHEET.md" ] && rm -f "$TMUX_CONF_DIR/CHEATSHEET.md"

  # TPM + plugins fleetmux installed (only if TPM itself is present — never
  # touches a TPM the user set up independently for a DIFFERENT config).
  if [ -d "$TPM_DIR" ]; then
    rm -rf "$HOME/.tmux/plugins"
    ok "Removed TPM + plugins: $HOME/.tmux/plugins"
  fi

  # Starship config: only if it's our sentinel-marked file; a `.fleetmux`
  # reference copy (written when the user chose [K]eep during install) is
  # also ours to remove. Never touches a config that kept the user's own.
  if [ -f "$STARSHIP_CONF" ] && grep -qF "$FLEETMUX_SENTINEL" "$STARSHIP_CONF" 2>/dev/null; then
    rm -f "$STARSHIP_CONF"
    ok "Removed: $STARSHIP_CONF"
  fi
  rm -f "${STARSHIP_CONF}.fleetmux"

  # Shell RC init lines: remove exactly the two lines we appended (sentinel
  # comment + the eval line immediately after it) — never touches anything
  # else in the user's rc file.
  _strip_sentinel_block() {
    local rc_file="$1"
    [ -f "$rc_file" ] || return 0
    if grep -qF "$FLEETMUX_SENTINEL" "$rc_file" 2>/dev/null; then
      local tmp
      tmp="$(mktemp)"
      awk -v sentinel="$FLEETMUX_SENTINEL" '
        $0 == sentinel { skip = 2; next }
        skip > 0 { skip--; next }
        { print }
      ' "$rc_file" > "$tmp"
      mv "$tmp" "$rc_file"
      ok "Removed fleetmux init lines from $rc_file"
    fi
  }
  _strip_sentinel_block "$HOME/.bashrc"
  _strip_sentinel_block "$HOME/.zshrc"

  # Ghostty config: only the fleetmux-managed file; app/binary is left alone.
  GHOSTTY_CONF="$HOME/.config/ghostty/config"
  if [ -f "$GHOSTTY_CONF" ] && grep -qF "$FLEETMUX_SENTINEL" "$GHOSTTY_CONF" 2>/dev/null; then
    rm -f "$GHOSTTY_CONF"
    ok "Removed: $GHOSTTY_CONF"
  fi

  # fleetmux-start
  if [ -f "$LOCAL_BIN/fleetmux-start" ]; then
    rm -f "$LOCAL_BIN/fleetmux-start"
    ok "Removed: $LOCAL_BIN/fleetmux-start"
  fi

  printf '\n  %sfleetmux removed.%s\n\n' "$C_GREEN" "$C_RESET"
  echo "  Left in place (fleetmux never removes these automatically):"
  echo "    • tmux / starship / fish / ghostty BINARIES — uninstall yourself via"
  echo "      brew/apt/dnf if you no longer want them for anything else"
  BAK_COUNT="$(find "$HOME" -maxdepth 3 -name '*.bak-*' 2>/dev/null | grep -cE '\.(bak)-[0-9]{14}$' || true)"
  if [ "${BAK_COUNT:-0}" -gt 0 ]; then
    echo "    • ${BAK_COUNT} timestamped backup(s) of your pre-fleetmux config(s) — find with:"
    echo "        find \"\$HOME\" -maxdepth 3 -name '*.bak-*'"
  fi
  CURRENT_LOGIN_SHELL="$(basename "${SHELL:-}")"
  if [ "$CURRENT_LOGIN_SHELL" = "fish" ]; then
    echo "    • your login shell is still fish — revert with: chsh -s /bin/bash  (or your prior shell)"
  fi
  exit 0
fi

# ── OS detect ─────────────────────────────────────────────────────────────────
OS_KIND="$(uname -s)"
IN_WSL=false
if [ -f /proc/version ] && grep -qi 'microsoft\|wsl' /proc/version 2>/dev/null; then
  IN_WSL=true
fi

# ── shared: fixed-path binary detection ───────────────────────────────────────
# `command -v` alone only sees what's on THIS process's PATH — which is
# incomplete in two real cases: (1) this script runs as a non-login,
# non-interactive shell (`bash <(curl ...)` does NOT source .zprofile/
# .bash_profile, so a Homebrew-provided binary can be genuinely installed yet
# invisible here), and (2) a component was installed by some OTHER method
# (starship's own curl installer defaults to ~/.local/bin; a user's own
# manual install could be anywhere). Every per-component detect->skip check
# below uses this instead of a bare `command -v` so "already installed" is
# answered by REALITY, not by "is it on PATH in this exact process" — the
# distinction that matters for never reinstalling something that's already
# there under a different install method.
# Echoes the resolved absolute path (PATH first, then each fixed candidate in
# order) and returns 0, or returns 1 if none resolve. `_binary_present`
# below is the boolean-only convenience wrapper most call sites want.
_resolve_bin() {
  local name="$1"
  shift
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi
  for path in "$@"; do
    if [ -x "$path" ]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  return 1
}

_binary_present() {
  _resolve_bin "$@" >/dev/null
}

_brew_candidates() {
  printf '%s\n' "/opt/homebrew/bin/brew" "/usr/local/bin/brew"
}

# Resolves an ALREADY-installed Homebrew into THIS process's PATH (see the
# non-login-shell note above) — every later `command -v brew`/`tmux`/
# `starship`/`fish` check in this script benefits once shellenv is sourced.
# Idempotent no-op if brew is already on PATH or genuinely absent.
_resolve_brew_path() {
  command -v brew >/dev/null 2>&1 && return 0
  for candidate in $(_brew_candidates); do
    if [ -x "$candidate" ]; then
      eval "$("$candidate" shellenv)"
      return 0
    fi
  done
  return 1
}
_resolve_brew_path || true

# ── step 0: Homebrew bootstrap (macOS only — Linux package managers don't
# need it) ─────────────────────────────────────────────────────────────────
if [ "$OS_KIND" = "Darwin" ]; then
  step "Step 0 — Homebrew"
  if command -v brew >/dev/null 2>&1; then
    ok "Homebrew already installed ($(brew --version | head -1))"
  else
    info "Homebrew not found — installing it now via Homebrew's OFFICIAL installer (https://brew.sh)."
    warn "This may prompt for YOUR MAC PASSWORD, in THIS terminal. fleetmux never"
    warn "captures, automates, or scripts past that prompt — it's Homebrew's own,"
    warn "unmodified installer; type your password only if and when Homebrew itself asks."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    _resolve_brew_path || true
    command -v brew >/dev/null 2>&1 || fail "Homebrew install finished but 'brew' is still not on PATH. Open a new terminal and re-run."
    ok "Homebrew installed ($(brew --version | head -1))"
  fi
fi

# ── step 1: OS detect + tmux install ─────────────────────────────────────────
step "Step 1 — Detect OS and install tmux"

_install_tmux_macos() {
  if command -v brew >/dev/null 2>&1; then
    brew install tmux
  else
    fail "Homebrew is required to install tmux on macOS but wasn't found even after the bootstrap step. Install from https://brew.sh then re-run."
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

TMUX_FIXED_PATHS="/opt/homebrew/bin/tmux /usr/local/bin/tmux /usr/bin/tmux"

case "$OS_KIND" in
  Darwin)
    ok "macOS"
    if ! _binary_present tmux $TMUX_FIXED_PATHS; then
      info "Installing tmux via Homebrew…"
      _install_tmux_macos
    else
      TMUX_BIN="$(_resolve_bin tmux $TMUX_FIXED_PATHS)"
      ok "tmux already installed ✓ ($("$TMUX_BIN" -V))"
    fi
    ;;
  Linux)
    if $IN_WSL; then
      warn "WSL2 detected. tmux works well in WSL2 but pane-title detection may differ from native Linux."
      warn "If pane titles don't show agent names, set them manually: printf '\\033]2;claude\\033\\\\'"
    else
      ok "Linux"
    fi
    if ! _binary_present tmux $TMUX_FIXED_PATHS; then
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
      TMUX_BIN="$(_resolve_bin tmux $TMUX_FIXED_PATHS)"
      ok "tmux already installed ✓ ($("$TMUX_BIN" -V))"
    fi
    ;;
  *)
    warn "Windows native is not supported. Use WSL2: https://learn.microsoft.com/en-us/windows/wsl/install"
    fail "Unsupported platform: $OS_KIND"
    ;;
esac

# Resolve tmux's bin path AGAIN here, unconditionally — covers the
# fresh-install branches above (which don't set TMUX_BIN themselves) and is a
# harmless re-resolve for the already-installed branches that did. A tmux
# found ONLY via a fixed path (not brew, so no shellenv to put it on PATH —
# e.g. apt/manual-compile/MacPorts installs) must not fall through to a bare
# `tmux` call below, which would fail with "command not found" even though
# tmux genuinely exists.
TMUX_BIN="$(_resolve_bin tmux $TMUX_FIXED_PATHS)" || fail "tmux install appeared to succeed but the binary still can't be found."

# Verify tmux version
TMUX_VER_RAW="$("$TMUX_BIN" -V 2>/dev/null | awk '{print $2}')"
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
  STARSHIP_FIXED_PATHS="/opt/homebrew/bin/starship /usr/local/bin/starship $HOME/.local/bin/starship /usr/bin/starship"
  if _binary_present starship $STARSHIP_FIXED_PATHS; then
    STARSHIP_BIN="$(_resolve_bin starship $STARSHIP_FIXED_PATHS)"
    ok "Starship already installed ✓ ($("$STARSHIP_BIN" --version 2>/dev/null | head -1))"
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

# ── step 9: Fish shell (strict opt-in) ────────────────────────────────────────
step "Step 9 — Fish shell (opt-in)"
if $OPT_WITH_FISH; then
  FISH_FIXED_PATHS="/opt/homebrew/bin/fish /usr/local/bin/fish /usr/bin/fish"
  if _binary_present fish $FISH_FIXED_PATHS; then
    FISH_BIN_EXISTING="$(_resolve_bin fish $FISH_FIXED_PATHS)"
    ok "Fish already installed ✓ ($("$FISH_BIN_EXISTING" --version 2>/dev/null))"
  else
    info "Installing Fish shell…"
    case "$OS_KIND" in
      Darwin)
        if command -v brew >/dev/null 2>&1; then
          brew install fish
        else
          fail "Homebrew is required to install Fish on macOS but wasn't found even after the bootstrap step. Install from https://brew.sh then re-run."
        fi
        ;;
      Linux)
        LINUX_ID=""
        if [ -r /etc/os-release ]; then
          # shellcheck disable=SC1091
          . /etc/os-release
          LINUX_ID="${ID:-}"
        fi
        case "$LINUX_ID" in
          ubuntu|debian)      sudo apt-get update -qq && sudo apt-get install -y fish ;;
          fedora)             sudo dnf install -y fish ;;
          rhel|centos)        sudo yum install -y fish ;;
          *)                  fail "Unknown Linux distro '${LINUX_ID:-unknown}'. Install fish manually: https://fishshell.com/" ;;
        esac
        ;;
    esac
    ok "Fish installed ($(fish --version 2>/dev/null))"
  fi

  FISH_PATH="$(_resolve_bin fish $FISH_FIXED_PATHS)"
  CURRENT_LOGIN_SHELL="$(basename "${SHELL:-}")"

  if [ "$CURRENT_LOGIN_SHELL" = "fish" ]; then
    ok "Already using fish as login shell — skipping chsh"
  else
    warn "Changing your login shell to fish. Your bash/zsh aliases/functions are NOT auto-migrated."
    warn "Revert anytime: chsh -s ${SHELL:-/bin/bash}"

    if ! grep -qxF "$FISH_PATH" /etc/shells 2>/dev/null; then
      if command -v sudo >/dev/null 2>&1 && sudo sh -c "echo '$FISH_PATH' >> /etc/shells" 2>/dev/null; then
        ok "Registered $FISH_PATH in /etc/shells"
      else
        warn "Could not register $FISH_PATH in /etc/shells — chsh may fail."
        warn "Manual: sudo sh -c \"echo $FISH_PATH >> /etc/shells\""
      fi
    fi

    DO_CHSH=false
    if $OPT_YES; then
      DO_CHSH=true
    elif $IS_TTY; then
      printf '  Change login shell to fish now? [y/N]: '
      read -r FISH_CHSH_ANS
      case "${FISH_CHSH_ANS:-N}" in [Yy]*) DO_CHSH=true ;; esac
    else
      warn "Non-interactive without --yes — skipping chsh. Run manually: chsh -s $FISH_PATH"
    fi

    if $DO_CHSH; then
      if chsh -s "$FISH_PATH" 2>/dev/null; then
        ok "Login shell changed to fish ($FISH_PATH). Restart your terminal to take effect."
      else
        warn "chsh failed — change manually: chsh -s $FISH_PATH"
      fi
    fi
  fi

  if [ -d "$HOME/.config/fish" ]; then
    ok "Existing ~/.config/fish left untouched (fleetmux ships no fish config preset)"
  fi
  info "Starship + Nerd Font already configured above will work under fish automatically."
else
  info "Fish shell not requested (use --with-fish or --full to opt in)"
fi

# ── step 10: Ghostty terminal (strict opt-in) ─────────────────────────────────
step "Step 10 — Ghostty terminal (opt-in)"
if $OPT_WITH_GHOSTTY; then
  if $IN_WSL; then
    warn "Ghostty has no native Windows build — skipping inside WSL2. Install it on the Windows host instead."
  else
    GHOSTTY_INSTALLED=false
    if [ "$OS_KIND" = "Darwin" ] && [ -d "/Applications/Ghostty.app" ]; then
      GHOSTTY_INSTALLED=true
    elif command -v ghostty >/dev/null 2>&1; then
      GHOSTTY_INSTALLED=true
    fi

    if $GHOSTTY_INSTALLED; then
      ok "Ghostty already installed ✓ — skipping install"
    else
      case "$OS_KIND" in
        Darwin)
          if command -v brew >/dev/null 2>&1; then
            info "Installing Ghostty via Homebrew…"
            if brew install --cask ghostty 2>/dev/null; then
              ok "Ghostty installed"
              GHOSTTY_INSTALLED=true
            else
              warn "Homebrew cask install failed. Download manually: https://ghostty.org/download"
            fi
          else
            warn "Homebrew is required to install Ghostty on macOS but wasn't found even after the bootstrap step. Install from https://brew.sh, or download manually: https://ghostty.org/download"
          fi
          ;;
        Linux)
          LINUX_ID=""
          if [ -r /etc/os-release ]; then
            # shellcheck disable=SC1091
            . /etc/os-release
            LINUX_ID="${ID:-}"
          fi
          if [ "$LINUX_ID" = "fedora" ] && command -v dnf >/dev/null 2>&1; then
            info "Installing Ghostty via dnf…"
            if sudo dnf install -y ghostty 2>/dev/null; then
              ok "Ghostty installed"
              GHOSTTY_INSTALLED=true
            else
              warn "dnf install failed. Download manually: https://ghostty.org/download"
            fi
          else
            warn "No automated Ghostty install for this distro yet. Install manually: https://ghostty.org/download"
          fi
          ;;
      esac
    fi

    if $GHOSTTY_INSTALLED; then
      GHOSTTY_CONF="$HOME/.config/ghostty/config"
      GHOSTTY_CONF_PRESET=$(cat <<'CFG'
# fleetmux-managed — generated by fleetmux installer
# Customize at ~/.config/ghostty/config — see https://ghostty.org/docs/config
font-family = JetBrainsMono Nerd Font
cursor-style = block
shell-integration = detect
mouse-hide-while-typing = true
CFG
)
      mkdir -p "$(dirname "$GHOSTTY_CONF")"
      if [ -f "$GHOSTTY_CONF" ] && ! grep -q "$FLEETMUX_SENTINEL" "$GHOSTTY_CONF" 2>/dev/null; then
        TS="$(_ts)"
        cp "$GHOSTTY_CONF" "${GHOSTTY_CONF}.bak-${TS}"
        warn "Backed up existing $GHOSTTY_CONF → ${GHOSTTY_CONF}.bak-${TS}"
      fi
      printf '%s\n' "$GHOSTTY_CONF_PRESET" > "$GHOSTTY_CONF"
      ok "Ghostty config installed: $GHOSTTY_CONF"
      info "Set Ghostty as your default terminal via System Settings > Default Terminal (not done automatically)."
    fi
  fi
else
  info "Ghostty not requested (use --with-ghostty or --full to opt in)"
fi

# ── step 11: install fleetmux-start on PATH ───────────────────────────────────
step "Step 11 — Install fleetmux-start"
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

# ── step 12: done ─────────────────────────────────────────────────────────────
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
if $OPT_WITH_FISH; then
  printf '    • Fish shell                     %s\n' "$(command -v fish 2>/dev/null)"
fi
if $OPT_WITH_GHOSTTY && [ -f "$HOME/.config/ghostty/config" ]; then
  printf '    • Ghostty config                 %s\n' "$HOME/.config/ghostty/config"
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
