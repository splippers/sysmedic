#!/bin/bash
# SysMedic agent poller: one OpenCode round every 10 minutes. The round has the hospital MCP only (no shell, no edits).
# Pause without killing anything:  touch ~/.local/share/sysmedic-agent/PAUSE      resume: rm it.
A="$HOME/.local/share/sysmedic-agent"
cd "$HOME/projects" 2>/dev/null || cd "$HOME"
export OPENCODE_CONFIG="$A/opencode-poll.json"
OC=$HOME/.opencode/bin/opencode
. "$A/agent.env"        # MODEL=provider/model, MODEL_NAME=short name for votes, STANCE=how this agent argues
"$OC" run --help 2>&1 | grep -q -- --standalone && STANDALONE=--standalone
LOCK=; command -v flock >/dev/null 2>&1 && LOCK="flock -n $A/poll.lock"
while true; do
  if [ ! -e "$A/PAUSE" ]; then
    echo "== $(date '+%F %T') round"
    $LOCK timeout 540 "$OC" run $STANDALONE --model "$MODEL" "$(cat "$A/poll-prompt.txt")

YOUR MODEL: $MODEL_NAME (pass exactly this as model in every vote and sign posts with it).
YOUR STANCE: $STANCE" 2>&1 | tail -40
    tail -n 3000 "$A/poll.log" > "$A/poll.log.tmp" 2>/dev/null && mv "$A/poll.log.tmp" "$A/poll.log"
  else
    echo "== $(date '+%F %T') paused (rm $A/PAUSE to resume)"
  fi
  sleep "${INTERVAL:-600}"
done 2>&1 | tee -a "$A/poll.log"
