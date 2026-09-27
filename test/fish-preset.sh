#!/usr/bin/env bash
# Clean-box test for `install.sh --with-fish`: the fresh-machine report was "gst: unknown
# command, fish greeting on every pane, and a pane that opened /bin/sh instead of fish".
# This runs the REAL installer against a sandboxed $HOME (fake brew/git/chsh/sudo on PATH,
# repo served via file://, exactly like test/repeatability.sh) and asserts each symptom's
# fix landed:
#   1. the fish preset exists, defines the `gst` abbreviation and blanks the greeting
#   2. ~/.config/tmux/local.conf pins default-shell to fish
#   3. a tmux server started from that config opens fish in a new pane
#   4. --uninstall removes both files again (and only them)
# Steps 1's abbr/greeting checks and 3 need real fish and tmux; they are skipped (not
# failed) where those binaries are absent, e.g. a bare CI runner.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/fleetmux-fish.XXXXXX")"
trap 'tmux -L fmfishtest kill-server 2>/dev/null || true; rm -rf "$T"' EXIT
mkdir -p "$T/home/Library/Fonts" "$T/fakebin" "$T/logs"
: > "$T/home/Library/Fonts/FooNerdFontMono.ttf"   # skip the font step
: > "$T/logs/chsh.log"

REAL_FISH="$(command -v fish 2>/dev/null || true)"
for b in brew git chsh sudo; do
  cat > "$T/fakebin/$b" <<STUB
#!/bin/bash
echo "\$*" >> "$T/logs/$b.log"
case "$b" in
  brew) [ "\$1" = "--version" ] && echo "Homebrew 4.0.0"
        if [ "\$1" = "install" ] && [ "\$2" = "fish" ]; then printf '#!/bin/bash\necho "fish, version 3.7.0"\n' > "$T/fakebin/fish"; chmod +x "$T/fakebin/fish"; fi ;;
  git)  if [ "\$1" = "clone" ]; then d="\${*: -1}"; mkdir -p "\$d"; : > "\$d/tpm"; chmod +x "\$d/tpm"; fi ;;
esac
exit 0
STUB
  chmod +x "$T/fakebin/$b"
done
# Real fish and tmux are used when present (so abbreviations and the pane shell are really
# exercised); the fixed-path detector in install.sh finds /opt/homebrew/bin/fish on its own.
PATH_SANDBOX="$T/fakebin:/usr/bin:/bin:/usr/sbin:/sbin"
[ -n "$REAL_FISH" ] && PATH_SANDBOX="$PATH_SANDBOX:$(dirname "$REAL_FISH")"
command -v tmux >/dev/null && PATH_SANDBOX="$PATH_SANDBOX:$(dirname "$(command -v tmux)")"

run_install() {
  HOME="$T/home" SHELL="/bin/zsh" PATH="$PATH_SANDBOX" FLEETMUX_REPO_URL="file://$REPO" \
    bash "$REPO/bin/install.sh" "$@"
}

echo "=== install --with-fish --yes ==="
run_install --with-fish --yes --no-starship --no-font > "$T/logs/install.out" 2>&1 || { echo "INSTALL FAILED:"; tail -40 "$T/logs/install.out"; exit 1; }

fail=0
pass() { echo "PASS $1"; }
flunk() { echo "FAIL $1"; fail=1; }

PRESET="$T/home/.config/fish/conf.d/fleetmux.fish"
LOCAL="$T/home/.config/tmux/local.conf"

echo "=== 1. fish preset ==="
[ -f "$PRESET" ] && grep -q '^# fleetmux-managed' "$PRESET" && pass "preset installed with sentinel" || flunk "preset missing: $PRESET"
grep -q 'abbr -a -g gst git status' "$PRESET" && pass "preset defines gst" || flunk "no gst abbreviation in preset"
grep -q '^set -g fish_greeting$' "$PRESET" && pass "preset blanks the greeting" || flunk "greeting not blanked"
if [ -n "$REAL_FISH" ]; then
  abbrs="$(HOME="$T/home" "$REAL_FISH" -c 'abbr -l' 2>/dev/null || true)"
  printf '%s\n' "$abbrs" | grep -qx gst && pass "real fish loads the preset: gst is an abbreviation" || flunk "real fish: gst missing (abbr -l: $(printf '%s' "$abbrs" | tr '\n' ' '))"
  greeting="$(HOME="$T/home" "$REAL_FISH" -c 'echo -n "$fish_greeting"' 2>/dev/null || true)"
  [ -z "$greeting" ] && pass "real fish: greeting is empty" || flunk "real fish: greeting still '$greeting'"
else
  echo "SKIP real-fish checks (fish not installed here)"
fi

echo "=== 2. tmux default-shell pinned ==="
fish_path="$(grep '^set -g default-shell' "$LOCAL" 2>/dev/null | awk '{print $4}' || true)"
[ -n "$fish_path" ] && pass "local.conf: default-shell $fish_path" || flunk "local.conf has no default-shell: $(cat "$LOCAL" 2>/dev/null)"
grep -q 'chsh' "$T/logs/chsh.log" 2>/dev/null || grep -q -- '-s ' "$T/logs/chsh.log" 2>/dev/null; grep -q -- "-s $fish_path" "$T/logs/chsh.log" && pass "chsh -s $fish_path was requested (sandboxed)" || flunk "chsh not called with -s $fish_path (log: $(cat "$T/logs/chsh.log"))"
grep -q 'source-file -q ~/.config/tmux/local.conf' "$T/home/.config/tmux/tmux.conf" && pass "tmux.conf sources local.conf" || flunk "tmux.conf does not source local.conf"

echo "=== 3. a new pane opens fish ==="
if command -v tmux >/dev/null && [ -x "$fish_path" ]; then
  HOME="$T/home" tmux -L fmfishtest -f "$T/home/.config/tmux/tmux.conf" new-session -d -s probe 2>"$T/logs/tmux.err" || true
  sleep 1
  pane_cmd="$(HOME="$T/home" tmux -L fmfishtest display-message -p -t probe '#{pane_current_command}' 2>/dev/null || true)"
  [ "$pane_cmd" = "fish" ] && pass "pane_current_command = fish (was: whatever \$SHELL the server inherited)" || flunk "pane opened '$pane_cmd', not fish ($(cat "$T/logs/tmux.err"))"
  HOME="$T/home" tmux -L fmfishtest kill-server 2>/dev/null || true
else
  echo "SKIP tmux pane check (tmux or real fish not available)"
fi

echo "=== 4. --uninstall removes preset + local.conf ==="
run_install --uninstall --yes > "$T/logs/uninstall.out" 2>&1 || true
[ ! -f "$PRESET" ] && pass "preset removed" || flunk "preset still present after --uninstall"
[ ! -f "$LOCAL" ] && pass "local.conf removed" || flunk "local.conf still present after --uninstall"

echo
[ $fail -eq 0 ] && echo "FISH PRESET TEST: PASS" || { echo "FISH PRESET TEST: FAIL"; exit 1; }
