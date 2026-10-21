#!/bin/bash
# Starts the tmux workspace "agent": window poll (the 10-minute swarm poller) and window work (a shell for the engineer).
A="$HOME/.local/share/sysmedic-agent"
T=$(command -v tmux) || exit 1
mkdir -p "$HOME/projects"
$T has-session -t agent 2>/dev/null && exit 0
$T new-session -d -s agent -n work -c "$HOME/projects"
$T send-keys -t agent:work "cat $A/WORK.txt" Enter
$T new-window -d -t agent -n poll -c "$HOME/projects" "$A/poll.sh"
