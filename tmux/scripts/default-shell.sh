#!/usr/bin/env sh
# Set tmux's default shell from the account database, not the server's SHELL.
# macOS exposes it through dscacheutil; Linux and other Unix systems commonly
# expose it through getent. SHELL is used only as a last-resort fallback.

login_shell=""

if command -v getent >/dev/null 2>&1; then
  login_shell="$(getent passwd "$(id -u)" 2>/dev/null | awk -F: 'NR == 1 { print $7 }')"
fi

if [ -z "$login_shell" ] && command -v dscacheutil >/dev/null 2>&1; then
  login_shell="$(dscacheutil -q user -a uid "$(id -u)" 2>/dev/null | awk -F': ' '$1 == "shell" { print $2; exit }')"
fi

if [ -z "$login_shell" ]; then
  login_shell="${SHELL:-}"
fi

if [ -n "$login_shell" ] && [ -x "$login_shell" ]; then
  tmux set-option -g default-shell "$login_shell"
fi
