#!/usr/bin/env bash
# Fresh-machine diagnostic for FleetMux fish/tmux wiring.
# Simulates a brand-new macOS user account (no dotfiles, no fish config) and
# runs the installer with --full --yes, then reports which wiring landed and
# which did not.
#
# This is NOT a CI gate by itself; it produces a human-readable report that
# should match the owner's screenshot on a clean box:
#   - fish binary installed and login shell changed
#   - NO ~/.config/fish/config.fish  -> greeting shown, no git abbr
#   - NO default-shell in tmux.conf  -> split panes may launch /bin/sh
#   - installer still exits 0         -> silent partial failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEETMUX_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_ROOT="$(mktemp -d -t fleetmux-freshmachine)"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/home" "$TEST_ROOT/fakebin" "$TEST_ROOT/logs"

BREW_LOG="$TEST_ROOT/logs/brew.log"
GIT_LOG="$TEST_ROOT/logs/git.log"
: > "$BREW_LOG"
: > "$GIT_LOG"

# ── fake brew: "installs" tmux/starship/fish by dropping version-printing stubs
cat > "$TEST_ROOT/fakebin/brew" <<'BREW'
#!/bin/bash
echo "$*" >> "$BREW_LOG"
if [ "$1" = "--version" ]; then echo "Homebrew 4.0.0"; exit 0; fi
if [ "$1" = "install" ]; then
  shift
  for arg in "$@"; do
    case "$arg" in
      --cask) continue ;;
      tmux)     printf '#!/bin/bash\necho "tmux 3.6a"\n' > "$FAKEBIN/tmux"; chmod +x "$FAKEBIN/tmux" ;;
      starship) printf '#!/bin/bash\necho "starship 1.20.0"\n' > "$FAKEBIN/starship"; chmod +x "$FAKEBIN/starship" ;;
      fish)     printf '#!/bin/bash\necho "fish, version 3.7.0"\n' > "$FAKEBIN/fish"; chmod +x "$FAKEBIN/fish" ;;
      node|font-jetbrains-mono-nerd-font|ghostty) : ;;
    esac
  done
fi
exit 0
BREW

# ── fake git: just creates the TPM dest directory
cat > "$TEST_ROOT/fakebin/git" <<'GITSTUB'
#!/bin/bash
echo "$*" >> "$GIT_LOG"
if [ "$1" = "clone" ]; then
  dest="${*: -1}"
  mkdir -p "$dest"
  : > "$dest/tpm"
  chmod +x "$dest/tpm"
fi
exit 0
GITSTUB

chmod +x "$TEST_ROOT/fakebin/brew" "$TEST_ROOT/fakebin/git"

# ── fake sudo: pretends success but never mutates the real system
cat > "$TEST_ROOT/fakebin/sudo" <<'SUDOSTUB'
#!/bin/bash
# Never run the wrapped command; just claim success so the installer continues.
exit 0
SUDOSTUB
chmod +x "$TEST_ROOT/fakebin/sudo"

# ── fake chsh: logs the target shell and exits success
CHSH_LOG="$TEST_ROOT/logs/chsh-target.log"
: > "$CHSH_LOG"
cat > "$TEST_ROOT/fakebin/chsh" <<CHSHSTUB
#!/bin/bash
# Record the requested shell for the report
for arg in "\$@"; do
  case "\$arg" in -s) CHSH_TARGET="\${2:-}"; break ;; esac
done
printf '%s\\n' "\${CHSH_TARGET:-unknown}" > "$CHSH_LOG"
exit 0
CHSHSTUB
chmod +x "$TEST_ROOT/fakebin/chsh"

# Pre-seed nerd font marker so font install is skipped (not what we're testing).
mkdir -p "$TEST_ROOT/home/Library/Fonts"
: > "$TEST_ROOT/home/Library/Fonts/FooNerdFontMono.ttf"

# Simulate a fresh account: no shell RC files, no fish config.
# (We do not create .zshrc / .bashrc / .config/fish.)

export TEST_ROOT

# Run the installer exactly as the README shows, but with --full --yes.
env \
  HOME="$TEST_ROOT/home" \
  SHELL="/bin/zsh" \
  PATH="$TEST_ROOT/fakebin:/usr/bin:/bin:/usr/sbin:/sbin" \
  FAKEBIN="$TEST_ROOT/fakebin" \
  BREW_LOG="$BREW_LOG" \
  GIT_LOG="$GIT_LOG" \
  FLEETMUX_REPO_URL="file://$FLEETMUX_REPO" \
  bash "$FLEETMUX_REPO/bin/install.sh" --full --yes \
  > "$TEST_ROOT/logs/install.out" 2>&1 || {
    echo "INSTALLER EXITED NON-ZERO:"
    tail -80 "$TEST_ROOT/logs/install.out"
    exit 1
  }

# Preserve artifacts for inspection before the trap deletes them.
PERSIST_DIR="$FLEETMUX_REPO/tmp/fresh-machine-diagnose-$(date +%Y%m%d%H%M%S)"
mkdir -p "$PERSIST_DIR"
cp -R "$TEST_ROOT/logs" "$PERSIST_DIR/"
cp -R "$TEST_ROOT/home" "$PERSIST_DIR/"
echo "(logs copied to $PERSIST_DIR for post-mortem)"

# ── Report findings ──
echo ""
echo "=== Fresh-machine sandbox report ($TEST_ROOT) ==="
echo ""
echo "1. Installer exit code: 0 (reported success)"
echo ""

echo "2. fish binary installed?"
if [ -x "$TEST_ROOT/fakebin/fish" ]; then
  echo "   YES -> $TEST_ROOT/fakebin/fish"
  "$TEST_ROOT/fakebin/fish"
else
  echo "   NO"
fi
echo ""

echo "3. Login shell change requested?"
if [ -f "$TEST_ROOT/logs/chsh-target.log" ]; then
  echo "   YES -> $(cat "$TEST_ROOT/logs/chsh-target.log")"
else
  echo "   NO (chsh not invoked)"
fi
echo ""

echo "4. ~/.config/fish/config.fish created?"
if [ -f "$TEST_ROOT/home/.config/fish/config.fish" ]; then
  echo "   YES"
  echo "   --- content ---"
  cat "$TEST_ROOT/home/.config/fish/config.fish"
  echo "   --- end ---"
else
  echo "   NO -> fish greeting will print; git abbreviations absent."
fi
echo ""

echo "5. Starship wired into fish config?"
if [ -f "$TEST_ROOT/home/.config/fish/config.fish" ] && grep -q "starship init fish" "$TEST_ROOT/home/.config/fish/config.fish"; then
  echo "   YES"
else
  echo "   NO -> starship prompt only works if some OTHER rc sources it."
fi
echo ""

echo "6. Git abbreviations wired into fish config?"
if [ -f "$TEST_ROOT/home/.config/fish/config.fish" ] && grep -q "abbr.*gst" "$TEST_ROOT/home/.config/fish/config.fish"; then
  echo "   YES"
else
  echo "   NO -> 'gst' will be unknown command (matches owner's screenshot)."
fi
echo ""

echo "7. Fish greeting suppressed?"
if [ -f "$TEST_ROOT/home/.config/fish/config.fish" ] && grep -q "fish_greeting" "$TEST_ROOT/home/.config/fish/config.fish"; then
  echo "   YES"
else
  echo "   NO -> nested 'fish' commands will print greeting (matches owner's screenshot)."
fi
echo ""

echo "8. tmux default-shell set to fish?"
TMUX_CONF="$TEST_ROOT/home/.config/tmux/tmux.conf"
if [ -f "$TMUX_CONF" ]; then
  if grep -qE "^\s*set\s+-g\s+default-shell" "$TMUX_CONF"; then
    echo "   YES -> $(grep "default-shell" "$TMUX_CONF")"
  else
    echo "   NO -> new tmux panes inherit whatever SHELL tmux was started with."
    echo "        On a fresh account that can be /bin/zsh, /bin/bash, or even /bin/sh."
  fi
else
  echo "   NO tmux.conf found at all"
fi
echo ""

echo "9. tmux default-command set?"
if [ -f "$TMUX_CONF" ] && grep -qE "^\s*set\s+-g\s+default-command" "$TMUX_CONF"; then
  echo "   YES -> $(grep "default-command" "$TMUX_CONF")"
else
  echo "   NO"
fi
echo ""

echo "=== End report ==="
echo ""
echo "Artifacts kept at: $TEST_ROOT (will auto-delete on script exit)"
