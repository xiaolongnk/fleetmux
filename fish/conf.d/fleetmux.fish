# fleetmux-managed — minimal fish preset, installed with `--with-fish`.
# Lives in conf.d/ so it never touches your config.fish; delete this file (or run the
# installer with --uninstall) to remove it. Everything here is a plain fish default a
# fresh machine is missing, nothing opinionated.

# No "Welcome to fish" banner on every new pane.
set -g fish_greeting

# Starship prompt when available (the installer puts it on PATH).
if type -q starship
    starship init fish | source
end

# Agent CLIs installed via npm/nvm/uv land here on a fresh box; make the panes see them.
for d in ~/.local/bin ~/.npm-global/bin ~/.bun/bin ~/.cargo/bin /opt/homebrew/bin
    test -d $d; and fish_add_path -g $d
end

# Git abbreviations — the muscle-memory set (expand on space; `abbr -l` to list).
abbr -a -g g   git
abbr -a -g gst git status
abbr -a -g gaa git add --all
abbr -a -g gcm git commit -m
abbr -a -g gco git checkout
abbr -a -g gsw git switch
abbr -a -g gp  git push
abbr -a -g gpl git pull
abbr -a -g gl  git log --oneline -20
abbr -a -g gd  git diff
abbr -a -g gb  git branch

# Agent shortcuts.
abbr -a -g fs  fleetmux-start
abbr -a -g fd  fleetmux-doctor
