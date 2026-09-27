#!/usr/bin/env bash
# The agent status bar and jump keys come from the tmux-agent-status TPM plugin
# (github.com/xiaolongnk/tmux-agent-status) and from NOWHERE else. Before 1.3 this repo
# shipped its own copies of agent-status.sh / agent-jump.sh, tmux.conf hard-wired the jump
# keys to them and install.sh downloaded them into ~/.config/tmux/scripts. This test pins
# the migration so a copy can't quietly creep back:
#   1. repo:       no tmux/scripts/agent-*.sh, no test/agent-status.sh
#   2. tmux.conf:  declares @plugin 'xiaolongnk/tmux-agent-status', carries #{agent_status}
#                  in status-right, has no hand-written agent-jump binds / script paths
#   3. install.sh: run for real against a sandboxed $HOME (fake brew/git on PATH, repo via
#                  file:// — same rig as test/repeatability.sh) with stale pre-1.3 copies
#                  pre-seeded: clones the plugin next to TPM, does NOT download the scripts,
#                  removes the stale copies; a second run neither clones nor removes again
#   4. doctor:     passes the plugin/config checks on that install, and flags a stale copy
#   5. live tmux:  a server started from the installed config with the real plugin has the
#                  placeholder substituted and prefix+Enter bound (needs tmux + a plugin
#                  checkout: FLEETMUX_AGENT_STATUS_SRC=<dir>, else a shallow clone; SKIPped,
#                  not failed, when neither is available — e.g. an offline box)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/fleetmux-plugin.XXXXXX")"
# (`|| true`: under set -e a failing command in the EXIT trap becomes the script's exit status)
trap 'tmux -L fmplugtest kill-server 2>/dev/null || true; rm -rf "$T"' EXIT

fail=0
pass()  { echo "PASS $1"; }
flunk() { echo "FAIL $1"; fail=1; }
skip()  { echo "SKIP $1"; }

CONF="$REPO/tmux/tmux.conf"
PLUGIN_URL_RE='xiaolongnk/tmux-agent-status'

echo "=== 1. no local script copies in the repo ==="
for f in tmux/scripts/agent-status.sh tmux/scripts/agent-jump.sh test/agent-status.sh; do
  [ ! -e "$REPO/$f" ] && pass "$f absent" || flunk "$f still in the repo — the plugin is the only home for it"
done
# nothing under tmux/ or bin/ may run a script by those names from ~/.config/tmux
stray="$(grep -rnE 'config/tmux/scripts/agent-(status|jump)\.sh' "$REPO/tmux" "$REPO/bin" "$REPO/demo" 2>/dev/null || true)"
[ -z "$stray" ] && pass "no reference to ~/.config/tmux/scripts/agent-*.sh in tmux/ bin/ demo/" || flunk "stale references:"$'\n'"$stray"

echo "=== 2. tmux.conf consumes the plugin ==="
grep -qF "set -g @plugin 'xiaolongnk/tmux-agent-status'" "$CONF" && pass "declares @plugin 'xiaolongnk/tmux-agent-status'" || flunk "no @plugin 'xiaolongnk/tmux-agent-status' line"
grep -E '^set -g status-right ' "$CONF" | grep -qF '#{agent_status}' && pass "status-right carries the #{agent_status} placeholder" || flunk "status-right has no #{agent_status} placeholder"
! grep -qE '^[[:space:]]*bind[[:space:]].*agent-jump' "$CONF" && pass "no hand-written agent-jump binds" || flunk "tmux.conf still binds agent-jump.sh by hand"
! grep -qE '^[[:space:]]*[^#[:space:]].*agent-status\.sh' "$CONF" && pass "no direct #(agent-status.sh) call" || flunk "tmux.conf still calls agent-status.sh directly"
# the plugin line must precede TPM init, or TPM never sees it
plugin_line="$(grep -nF "@plugin 'xiaolongnk/tmux-agent-status'" "$CONF" | head -1 | cut -d: -f1)"
tpm_line="$(grep -nE "^run .*tpm/tpm" "$CONF" | head -1 | cut -d: -f1)"
[ -n "$plugin_line" ] && [ -n "$tpm_line" ] && [ "$plugin_line" -lt "$tpm_line" ] && pass "plugin declared before TPM init" || flunk "plugin declaration (line ${plugin_line:-?}) is not before run tpm (line ${tpm_line:-?})"

echo "=== 3. install.sh clones the plugin, ships no script copies, cleans pre-1.3 ones ==="
mkdir -p "$T/home/Library/Fonts" "$T/fakebin" "$T/logs" "$T/home/.config/tmux/scripts"
: > "$T/home/Library/Fonts/FooNerdFontMono.ttf"   # skip the font step
: > "$T/logs/git.log"; : > "$T/logs/brew.log"
# stale pre-1.3 copies, as an upgrade would find them
printf '#!/bin/bash\necho stale\n' > "$T/home/.config/tmux/scripts/agent-status.sh"
printf '#!/bin/bash\necho stale\n' > "$T/home/.config/tmux/scripts/agent-jump.sh"
chmod +x "$T/home/.config/tmux/scripts/agent-"*.sh

# A real plugin checkout when we can get one (needed for step 5); the fake git below
# copies it into place so the sandboxed install ends up with the genuine plugin files.
PLUGIN_SRC="${FLEETMUX_AGENT_STATUS_SRC:-}"
if [ -z "$PLUGIN_SRC" ] && command -v git >/dev/null 2>&1; then
  if GIT_TERMINAL_PROMPT=0 git clone -q --depth=1 https://github.com/xiaolongnk/tmux-agent-status "$T/plugin-src" 2>/dev/null; then
    PLUGIN_SRC="$T/plugin-src"
  fi
fi
[ -n "$PLUGIN_SRC" ] && [ -f "$PLUGIN_SRC/agent-status.tmux" ] || PLUGIN_SRC=""

cat > "$T/fakebin/brew" <<'BREW'
#!/bin/bash
echo "$*" >> "$BREW_LOG"
[ "$1" = "--version" ] && echo "Homebrew 4.0.0"
exit 0
BREW
cat > "$T/fakebin/git" <<GITSTUB
#!/bin/bash
echo "\$*" >> "$T/logs/git.log"
if [ "\$1" = "clone" ]; then
  dest="\${*: -1}"
  case "\$*" in
    *tmux-agent-status*)
      if [ -n "$PLUGIN_SRC" ]; then cp -R "$PLUGIN_SRC" "\$dest"
      else mkdir -p "\$dest/scripts"; : > "\$dest/agent-status.tmux"; : > "\$dest/scripts/agent-status.sh"; : > "\$dest/scripts/agent-jump.sh"; chmod +x "\$dest"/scripts/*.sh; fi ;;
    *) mkdir -p "\$dest"; : > "\$dest/tpm"; chmod +x "\$dest/tpm" ;;
  esac
fi
exit 0
GITSTUB
chmod +x "$T/fakebin/brew" "$T/fakebin/git"
PATH_SANDBOX="$T/fakebin:/usr/bin:/bin:/usr/sbin:/sbin"
command -v tmux >/dev/null && PATH_SANDBOX="$PATH_SANDBOX:$(dirname "$(command -v tmux)")"

run_install() {
  HOME="$T/home" SHELL="/bin/zsh" PATH="$PATH_SANDBOX" BREW_LOG="$T/logs/brew.log" FLEETMUX_REPO_URL="file://$REPO" \
    bash "$REPO/bin/install.sh" "$@"
}
run_install --yes --no-starship --no-font > "$T/logs/install1.out" 2>&1 || { echo "INSTALL FAILED:"; tail -40 "$T/logs/install1.out"; exit 1; }

PLUGIN="$T/home/.tmux/plugins/tmux-agent-status"
grep -qE "^clone .*$PLUGIN_URL_RE.* $PLUGIN\$" "$T/logs/git.log" && pass "git clone of the plugin into ~/.tmux/plugins/tmux-agent-status" || flunk "no plugin clone in git log: $(cat "$T/logs/git.log")"
[ -f "$PLUGIN/agent-status.tmux" ] && pass "plugin entry point present next to TPM" || flunk "$PLUGIN/agent-status.tmux missing"
[ -d "$T/home/.tmux/plugins/tpm" ] && pass "TPM still installed alongside" || flunk "TPM missing"
for s in agent-status.sh agent-jump.sh; do
  [ ! -e "$T/home/.config/tmux/scripts/$s" ] && pass "pre-1.3 copy scripts/$s removed" || flunk "scripts/$s still present after upgrade"
done
for s in firstrun-popup.sh firstrun-show.sh; do
  [ -x "$T/home/.config/tmux/scripts/$s" ] && pass "scripts/$s (still shipped) installed" || flunk "scripts/$s missing — cleanup was too greedy"
done
grep -qF "Removed pre-1.3 script copies" "$T/logs/install1.out" && pass "installer reported the cleanup" || flunk "installer did not report removing the pre-1.3 copies"
grep -qF "#{agent_status}" "$T/home/.config/tmux/tmux.conf" && pass "installed tmux.conf carries the placeholder" || flunk "installed tmux.conf has no placeholder"

run_install --yes --no-starship --no-font > "$T/logs/install2.out" 2>&1 || { echo "SECOND INSTALL FAILED:"; tail -40 "$T/logs/install2.out"; exit 1; }
[ "$(grep -c "^clone .*$PLUGIN_URL_RE" "$T/logs/git.log")" -eq 1 ] && pass "second run: plugin not cloned again" || flunk "second run cloned the plugin again"
! grep -qF "Removed pre-1.3 script copies" "$T/logs/install2.out" && pass "second run: nothing left to clean up" || flunk "second run claimed to remove copies again"
grep -qF "tmux-agent-status plugin already installed" "$T/logs/install2.out" && pass "second run: detect-then-skip" || flunk "second run did not detect the installed plugin"

echo "=== 4. doctor ==="
DOCTOR="$T/home/.local/bin/fleetmux-doctor"
[ -x "$DOCTOR" ] || { flunk "fleetmux-doctor not installed"; DOCTOR="$REPO/bin/doctor"; }
# sensible/resurrect/… are TPM's job (prefix + I), so the doctor legitimately fails overall
# on this sandbox; we look at the lines that belong to this migration.
dout="$(HOME="$T/home" SHELL=/bin/zsh PATH="$PATH_SANDBOX" bash "$DOCTOR" 2>&1 || true)"
printf '%s\n' "$dout" | grep -qF "✓ tmux-agent-status (status bar + jump keys)" && pass "doctor: plugin found" || flunk "doctor did not find the plugin:"$'\n'"$dout"
printf '%s\n' "$dout" | grep -qF "✓ tmux.conf declares the tmux-agent-status plugin" && pass "doctor: declaration found" || flunk "doctor: declaration check missing"
printf '%s\n' "$dout" | grep -qF "✓ status-right carries the #{agent_status} placeholder" && pass "doctor: placeholder found" || flunk "doctor: placeholder check missing"
! printf '%s\n' "$dout" | grep -qF "scripts/agent-status.sh" && pass "doctor: no longer expects scripts/agent-status.sh" || flunk "doctor still mentions scripts/agent-status.sh:"$'\n'"$dout"
: > "$T/home/.config/tmux/scripts/agent-jump.sh"
dout2="$(HOME="$T/home" SHELL=/bin/zsh PATH="$PATH_SANDBOX" bash "$DOCTOR" 2>&1 || true)"
printf '%s\n' "$dout2" | grep -qF "stale pre-1.3 copy scripts/agent-jump.sh" && pass "doctor: warns about a stale pre-1.3 copy" || flunk "doctor did not warn about a stale copy"
rm -f "$T/home/.config/tmux/scripts/agent-jump.sh"

echo "=== 5. live: the plugin fills the placeholder and binds the keys ==="
if command -v tmux >/dev/null 2>&1 && [ -n "$PLUGIN_SRC" ]; then
  # TPM stand-in that only initialises this plugin (a real TPM would clone the other four)
  printf '#!/bin/sh\nexec "$HOME/.tmux/plugins/tmux-agent-status/agent-status.tmux"\n' > "$T/home/.tmux/plugins/tpm/tpm"
  chmod +x "$T/home/.tmux/plugins/tpm/tpm"
  conf="$T/home/.config/tmux/tmux.conf"
  grep -v 'set-hook -g session-created' "$conf" > "$T/tmux.conf"   # no tty for display-popup here
  HOME="$T/home" tmux -L fmplugtest -f "$T/tmux.conf" new-session -d -s probe 2>"$T/logs/tmux.err" || true
  sleep 1
  sr="$(HOME="$T/home" tmux -L fmplugtest show-options -gv status-right 2>/dev/null || true)"
  case "$sr" in
    *"$PLUGIN/scripts/agent-status.sh"*) pass "status-right now runs the plugin's agent-status.sh" ;;
    *'#{agent_status}'*) flunk "placeholder was not substituted: $sr ($(cat "$T/logs/tmux.err"))" ;;
    *) flunk "unexpected status-right: '$sr' ($(cat "$T/logs/tmux.err"))" ;;
  esac
  keys="$(HOME="$T/home" tmux -L fmplugtest list-keys 2>/dev/null || true)"
  printf '%s\n' "$keys" | grep -E '^bind-key .* Enter +run-shell ' | grep -q 'agent-jump.sh waiting' && pass "prefix + Enter → agent-jump.sh waiting (bound by the plugin)" || flunk "prefix + Enter not bound by the plugin"
  printf '%s\n' "$keys" | grep -E '^bind-key .* Tab +run-shell ' | grep -q 'agent-jump.sh any' && pass "prefix + Tab → agent-jump.sh any" || flunk "prefix + Tab not bound by the plugin"
  printf '%s\n' "$keys" | grep -E '^bind-key .* a +run-shell ' | grep -q 'agent-jump.sh claude' && pass "prefix + a → agent-jump.sh claude" || flunk "prefix + a not bound by the plugin"
  ! printf '%s\n' "$keys" | grep -q 'config/tmux/scripts/agent-jump' && pass "no binding points at ~/.config/tmux/scripts" || flunk "a binding still points at ~/.config/tmux/scripts"
  HOME="$T/home" tmux -L fmplugtest kill-server 2>/dev/null || true
else
  skip "live tmux check (needs tmux and a plugin checkout — set FLEETMUX_AGENT_STATUS_SRC or allow a git clone)"
fi

echo
[ $fail -eq 0 ] && echo "PLUGIN CONSUMPTION TEST: PASS" || { echo "PLUGIN CONSUMPTION TEST: FAIL"; exit 1; }
