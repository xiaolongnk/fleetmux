# README demo — recorded with `vhs demo/demo.tape` from the repo root.
# Shows the real status bar + real jump bindings against fake agent CLIs (demo/fake-agent.sh)
# that paint the screens the real ones show. Re-record after changing the status bar.
Output docs/assets/fleetmux-demo.gif

Set Shell bash
Set FontSize 15
Set Width 1180
Set Height 640
Set Padding 12
Set Theme "Catppuccin Mocha"
Set TypingSpeed 40ms

Hide
Type "source demo/setup.sh" Enter
Sleep 2s
Show

# 1. Four agents, already running — the bar counts them and shows who is waiting (●)
Sleep 2.5s

# 2. prefix+Enter → next agent that needs you (the approval prompt)
Ctrl+q
Enter
Sleep 2s

# 3. again → the idle one
Ctrl+q
Enter
Sleep 2s

# 4. prefix+e → cycle Codex panes
Ctrl+q
Type "e"
Sleep 1.5s

# 5. a shell pane with the probe's raw view
Ctrl+q
Type "c"
Sleep 0.6s
Type "~/.tmux/plugins/tmux-agent-status/scripts/agent-status.sh --list | column -t -s $'\t'" Enter
Sleep 3.5s
