#!/bin/bash
# Install Ollama + JonotronV3 from persistence partition
# Run after mounting SYSMEDIC_PERSIST

PERSIST_DIR="/mnt/persist"
OLLAMA_BIN="$PERSIST_DIR/bin/ollama"
MODEL_FILE="$PERSIST_DIR/models/jonotron-v3-q4_k_m.gguf"
MODELLE_FILE="$PERSIST_DIR/models/Modelfile"
MODELLE_FALLBACK="/opt/sysmedic/models/Modelfile"

[ -f "$OLLAMA_BIN" ] || { echo "Ollama not found at $OLLAMA_BIN"; exit 1; }
[ -f "$MODEL_FILE" ] || { echo "Model not found at $MODEL_FILE"; exit 1; }

echo "Starting Ollama server..."
export OLLAMA_MODELS="$PERSIST_DIR/ollama-models"
mkdir -p "$OLLAMA_MODELS" "$PERSIST_DIR/logs"
nohup "$OLLAMA_BIN" serve > "$PERSIST_DIR/logs/ollama.log" 2>&1 &
sleep 3

echo "Creating JonotronV3 model with tool support..."
MODELLE_SRC="$MODELLE_FILE"
[ ! -f "$MODELLE_SRC" ] && MODELLE_SRC="$MODELLE_FALLBACK"

cat > /tmp/jonotron-modelfile << TMODEL
$(cat "$MODELLE_SRC" | sed "s|FROM .*|FROM $MODEL_FILE|")
TMODEL

"$OLLAMA_BIN" create jonotron-v3 -f /tmp/jonotron-modelfile 2>&1
echo ""
echo "Done! Model 'jonotron-v3' ready with tool calling support"
echo "Test: curl http://localhost:11434/api/tags"
