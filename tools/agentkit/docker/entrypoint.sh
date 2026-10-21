#!/bin/bash
# One work unit. Needs env: UNIT_NAME (informational), MODEL, MODEL_NAME, STANCE. First start also needs /run/secrets/pair (a pairing code).
A="$HOME/.local/share/sysmedic-agent"
mkdir -p "$A" "$HOME/projects" "$HOME/.config/opencode" "$SYSMEDIC_HOSPITAL_DIR"
for f in poll.sh session.sh WORK.txt opencode-poll.json poll-prompt.txt; do cp "/opt/agentkit/$f" "$A/$f"; done
chmod +x "$A/poll.sh" "$A/session.sh"
printf 'MODEL=%s\nMODEL_NAME="%s"\nSTANCE="%s"\nOC=%s\n' "$MODEL" "$MODEL_NAME" "$STANCE" "$HOME/.opencode/bin/opencode" > "$A/agent.env"
cat > "$HOME/.config/opencode/opencode.json" <<JSON
{ "\$schema": "https://opencode.ai/config.json",
  "mcp": { "hospital": { "type": "local", "command": ["/usr/local/bin/sysmedic-hospital", "mcp"], "enabled": true, "timeout": 40000 } },
  "permission": { "hospital_*": "allow" } }
JSON
if [ -f /run/secrets/pair ] && [ ! -f "$SYSMEDIC_HOSPITAL_DIR/.paired" ]; then
  sysmedic-hospital pair < /run/secrets/pair > "$A/pair.out" 2>&1 && touch "$SYSMEDIC_HOSPITAL_DIR/.paired"
  sed 's/H1\.[A-Za-z0-9_=-]*/<code>/g' "$A/pair.out" | tail -3
fi
grep -q 'sysmedic-agent' ~/.bashrc 2>/dev/null || cat /opt/agentkit/bashrc-block >> ~/.bashrc
sh "$A/session.sh"
# the container lives as long as the tmux session does; if it dies, exit so the restart policy brings it back
while tmux has-session -t agent 2>/dev/null; do sleep 10; done
echo "tmux session ended"; exit 1
