#!/usr/bin/env bash
# Repeatability/idempotency test for bin/install.sh — the "running the
# installer N times = same end state" acceptance criterion from the fleetmux
# design doc (docs/plans/termio-agent-tmux-distro.md upstream). Runs the REAL
# install.sh script body TWICE against a fully sandboxed $HOME, with brew and
# git faked as PATH stubs (see fakebin/ below) so this NEVER touches real
# Homebrew, never hits the real network for a package install, and never
# runs a real `chsh` (this test never passes --with-fish). REPO_URL is
# pointed at this checkout via file://, so the tmux.conf/scripts/cheatsheet
# downloads read the repo's own working tree instead of the network.
#
# Usage: bash test/repeatability.sh   (run from anywhere; paths are
# resolved relative to this script's own location, not $PWD)
#
# Exit 0 + "REPEATABILITY TEST: PASS" on success; nonzero + a labeled failure
# otherwise. Wired into .github/workflows/repeatability.yml (macos-latest).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEETMUX_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_ROOT="$(mktemp -d -t fleetmux-repeatability)"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/home" "$TEST_ROOT/fakebin" "$TEST_ROOT/logs"

BREW_LOG="$TEST_ROOT/logs/brew.log"
GIT_LOG="$TEST_ROOT/logs/git.log"
: > "$BREW_LOG"
: > "$GIT_LOG"

# ── fake brew — logs every call; "installs" tmux/starship/fish by dropping a
# version-printing stub into the fake bin dir; never touches real Homebrew ──
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

# ── fake git — only TPM's `git clone` call; no real network ────────────────
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

# Nerd font: pre-seed a marker so the detector finds it and skips any font
# install path (real or fake) entirely — this test isn't about fonts.
mkdir -p "$TEST_ROOT/home/Library/Fonts"
: > "$TEST_ROOT/home/Library/Fonts/FooNerdFontMono.ttf"
: > "$TEST_ROOT/home/.zshrc"

run_install() {
  local n="$1"
  echo "=== RUN $n ==="
  HOME="$TEST_ROOT/home" \
  SHELL="/bin/zsh" \
  PATH="$TEST_ROOT/fakebin:/usr/bin:/bin:/usr/sbin:/sbin" \
  FAKEBIN="$TEST_ROOT/fakebin" \
  BREW_LOG="$BREW_LOG" \
  GIT_LOG="$GIT_LOG" \
  FLEETMUX_REPO_URL="file://$FLEETMUX_REPO" \
    bash "$FLEETMUX_REPO/bin/install.sh" --yes
}

run_install 1 > "$TEST_ROOT/logs/run1.out" 2>&1 || { echo "RUN 1 FAILED:"; cat "$TEST_ROOT/logs/run1.out"; exit 1; }
cp "$BREW_LOG" "$TEST_ROOT/logs/brew-after-run1.log"
cp "$GIT_LOG" "$TEST_ROOT/logs/git-after-run1.log"

find "$TEST_ROOT/home" -type f -o -type l 2>/dev/null | sort > "$TEST_ROOT/logs/filelist-after-run1.txt"
: > "$TEST_ROOT/logs/content-after-run1.txt"
for f in "$TEST_ROOT/home/.config/tmux/tmux.conf" "$TEST_ROOT/home/.config/starship.toml" "$TEST_ROOT/home/.zshrc"; do
  [ -f "$f" ] && { echo "--- $f ---"; cat "$f"; } >> "$TEST_ROOT/logs/content-after-run1.txt"
done

run_install 2 > "$TEST_ROOT/logs/run2.out" 2>&1 || { echo "RUN 2 FAILED:"; cat "$TEST_ROOT/logs/run2.out"; exit 1; }

find "$TEST_ROOT/home" -type f -o -type l 2>/dev/null | sort > "$TEST_ROOT/logs/filelist-after-run2.txt"
: > "$TEST_ROOT/logs/content-after-run2.txt"
for f in "$TEST_ROOT/home/.config/tmux/tmux.conf" "$TEST_ROOT/home/.config/starship.toml" "$TEST_ROOT/home/.zshrc"; do
  [ -f "$f" ] && { echo "--- $f ---"; cat "$f"; } >> "$TEST_ROOT/logs/content-after-run2.txt"
done

echo ""
echo "=== CHECK: file list run1 vs run2 (must be identical) ==="
if ! diff -q "$TEST_ROOT/logs/filelist-after-run1.txt" "$TEST_ROOT/logs/filelist-after-run2.txt" > /dev/null; then
  echo "FAIL — file set changed between runs:"
  diff "$TEST_ROOT/logs/filelist-after-run1.txt" "$TEST_ROOT/logs/filelist-after-run2.txt"
  exit 1
fi
echo "PASS (identical file set)"

echo ""
echo "=== CHECK: config content run1 vs run2 (must be identical — no duplicate blocks) ==="
if ! diff -q "$TEST_ROOT/logs/content-after-run1.txt" "$TEST_ROOT/logs/content-after-run2.txt" > /dev/null; then
  echo "FAIL — config content changed between runs:"
  diff "$TEST_ROOT/logs/content-after-run1.txt" "$TEST_ROOT/logs/content-after-run2.txt"
  exit 1
fi
echo "PASS (identical content)"

echo ""
echo "=== CHECK: zero 'brew install' calls on run 2 (--version queries are fine) ==="
run2_brew_installs="$(comm -13 <(sort "$TEST_ROOT/logs/brew-after-run1.log") <(sort "$BREW_LOG") | grep '^install ' || true)"
if [ -n "$run2_brew_installs" ]; then
  echo "FAIL — unexpected brew install call(s) on run 2:"
  echo "$run2_brew_installs"
  exit 1
fi
echo "PASS (run 2 made zero brew install calls)"

echo ""
echo "=== CHECK: zero 'git clone' calls on run 2 (TPM already present) ==="
run2_git_calls="$(comm -13 <(sort "$TEST_ROOT/logs/git-after-run1.log") <(sort "$GIT_LOG") || true)"
if [ -n "$run2_git_calls" ]; then
  echo "FAIL — unexpected git call(s) on run 2:"
  echo "$run2_git_calls"
  exit 1
fi
echo "PASS (run 2 made zero git clone calls)"

echo ""
echo "=== CHECK: no duplicate '# fleetmux-managed' sentinel blocks ==="
SENTINEL_FILES="$TEST_ROOT/home/.zshrc"
for f in $SENTINEL_FILES; do
  count=$(grep -c '# fleetmux-managed' "$f" 2>/dev/null || echo 0)
  if [ "$count" -gt 1 ]; then
    echo "FAIL — duplicate sentinel blocks in $f ($count occurrences)"
    exit 1
  fi
done
echo "PASS (no duplicate sentinel blocks)"

echo ""
echo "REPEATABILITY TEST: PASS"
