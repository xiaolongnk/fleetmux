#!/usr/bin/env bash
# CI gate: --full install wires fish into tmux and writes a fish config.
# Simulates a clean macOS account with faked brew/git/sudo/chsh so no real
# system state is mutated. Exits 0 on success, nonzero with a labeled failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEETMUX_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_ROOT="$(mktemp -d -t fleetmux-fish-wiring)"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/home" "$TEST_ROOT/fakebin" "$TEST_ROOT/logs"

BREW_LOG="$TEST_ROOT/logs/brew.log"
GIT_LOG="$TEST_ROOT/logs/git.log"
CHSH_LOG="$TEST_ROOT/logs/chsh-target.log"
: > "$BREW_LOG"
: > "$GIT_LOG"
: > "$CHSH_LOG"

# ── fake brew ──
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

# ── fake git ──
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

# ── fake sudo: never mutates the real system ──
cat > "$TEST_ROOT/fakebin/sudo" <<'SUDOSTUB'
#!/bin/bash
exit 0
SUDOSTUB

# ── fake chsh: records requested shell ──
cat > "$TEST_ROOT/fakebin/chsh" <<CHSHSTUB
#!/bin/bash
for arg in "\$@"; do
  case "\$arg" in -s) CHSH_TARGET="\${2:-}"; break ;; esac
done
printf '%s\\n' "\${CHSH_TARGET:-unknown}" > "$CHSH_LOG"
exit 0
CHSHSTUB

chmod +x "$TEST_ROOT/fakebin/brew" "$TEST_ROOT/fakebin/git" "$TEST_ROOT/fakebin/sudo" "$TEST_ROOT/fakebin/chsh"

# Pre-seed nerd font marker so font install is skipped.
mkdir -p "$TEST_ROOT/home/Library/Fonts"
: > "$TEST_ROOT/home/Library/Fonts/FooNerdFontMono.ttf"

# Fresh account: no dotfiles at all.

run_install() {
  HOME="$TEST_ROOT/home" \
  SHELL="/bin/zsh" \
  PATH="$TEST_ROOT/fakebin:/usr/bin:/bin:/usr/sbin:/sbin" \
  FAKEBIN="$TEST_ROOT/fakebin" \
  BREW_LOG="$BREW_LOG" \
  GIT_LOG="$GIT_LOG" \
  FLEETMUX_REPO_URL="file://$FLEETMUX_REPO" \
    bash "$FLEETMUX_REPO/bin/install.sh" --full --yes
}

run_install > "$TEST_ROOT/logs/install.out" 2>&1 || {
  echo "INSTALLER FAILED:"
  tail -100 "$TEST_ROOT/logs/install.out"
  exit 1
}

TMUX_CONF="$TEST_ROOT/home/.config/tmux/tmux.conf"
FISH_CONF="$TEST_ROOT/home/.config/fish/config.fish"

fail() {
  echo "FAIL: $*"
  exit 1
}

echo ""
echo "=== CHECK: fish config exists ==="
[ -f "$FISH_CONF" ] || fail "Fish config not created: $FISH_CONF"
echo "PASS"

echo ""
echo "=== CHECK: fish greeting suppressed ==="
grep -qF "set -g fish_greeting" "$FISH_CONF" || fail "fish_greeting not set in $FISH_CONF"
echo "PASS"

echo ""
echo "=== CHECK: starship initialized in fish ==="
grep -qF "starship init fish | source" "$FISH_CONF" || fail "starship not initialized in $FISH_CONF"
echo "PASS"

echo ""
echo "=== CHECK: git abbreviations present (owner's 'gst' muscle memory) ==="
grep -qF "abbr -a gst" "$FISH_CONF" || fail "'abbr -a gst' missing in $FISH_CONF"
echo "PASS"

echo ""
echo "=== CHECK: tmux default-shell set to fish ==="
[ -f "$TMUX_CONF" ] || fail "tmux.conf not created: $TMUX_CONF"
grep -qE '^\s*set\s+-g\s+default-shell' "$TMUX_CONF" || fail "tmux default-shell not set"
echo "PASS"

echo ""
echo "=== CHECK: login shell change was requested ==="
[ -s "$CHSH_LOG" ] || fail "chsh was not invoked"
echo "PASS -> $(cat "$CHSH_LOG")"

echo ""
echo "FISH WIRING TEST: PASS"
