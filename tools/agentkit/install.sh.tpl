#!/bin/sh
# SysMedic ThoughtFarm agent workspace for @NAME@ (model @MODELNAME@). Safe to run again.
# Changes only: ~/.local/share/sysmedic-agent, ~/projects, one user service (or a Termux boot hook), one block in ~/.bashrc.
set -e
A="$HOME/.local/share/sysmedic-agent"
OC=$(command -v opencode || true)
[ -n "$OC" ] || { [ -x "$HOME/.opencode/bin/opencode" ] && OC="$HOME/.opencode/bin/opencode"; } || true
[ -n "$OC" ] || { echo "OpenCode is not installed here. Install it first, then run this again."; exit 1; }
[ -x "$HOME/.local/bin/sysmedic-hospital" ] || command -v sysmedic-hospital >/dev/null 2>&1 || { echo "No hospital client here. Run: curl -fsSk @URL@/install | sh   then pair it, then run this again."; exit 1; }
if ! command -v tmux >/dev/null 2>&1; then
  if command -v pkg >/dev/null 2>&1; then pkg install -y tmux
  elif command -v apt-get >/dev/null 2>&1; then sudo -n apt-get install -y tmux || { echo "Could not install tmux: run  sudo apt-get install -y tmux  then run this again."; exit 1; }
  else echo "Install tmux, then run this again."; exit 1; fi
fi
mkdir -p "$A" "$HOME/projects"
@FILES@
cat > "$A/agent.env" <<'SYSMEDIC_EOF'
@ENV@
SYSMEDIC_EOF
printf 'OC="%s"\n' "$OC" >> "$A/agent.env"
chmod +x "$A/poll.sh" "$A/session.sh"
grep -q "sysmedic-agent" "$HOME/.bashrc" 2>/dev/null || cat "$A/bashrc-block" >> "$HOME/.bashrc"
grep -q '"hospital"' "$HOME/.config/opencode/opencode.json" 2>/dev/null || echo "NOTE: OpenCode here has no hospital MCP entry yet (run install-swarm from the engineer's PC), so the poller cannot reach the board."
if systemctl --user show-environment >/dev/null 2>&1; then
  mkdir -p "$HOME/.config/systemd/user"
  cp "$A/sysmedic-agent-tmux.service" "$HOME/.config/systemd/user/"
  sudo -n loginctl enable-linger "$USER" 2>/dev/null || true
  systemctl --user daemon-reload
  systemctl --user enable sysmedic-agent-tmux.service
  systemctl --user restart sysmedic-agent-tmux.service
  echo "started as a user service (survives reboot)"
else
  tmux kill-session -t agent 2>/dev/null || true
  sh "$A/session.sh"
  mkdir -p "$HOME/.termux/boot"
  printf '#!/bin/sh\ntermux-wake-lock 2>/dev/null\nsh %s/session.sh\n' "$A" > "$HOME/.termux/boot/sysmedic-agent"
  chmod +x "$HOME/.termux/boot/sysmedic-agent"
  echo "started in tmux; restarts at boot only if Termux:Boot is installed"
fi
sleep 2; tmux ls
echo "Join the workspace with: tmux attach -t agent"
