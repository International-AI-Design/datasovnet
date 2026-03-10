#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────
# DataSovNet Coordinator
# Manages the distributed compute network
# Runs on the coordinator node (Johnny's M3 Max)
# ─────────────────────────────────────────────────────────

DATASOVNET_DIR="$HOME/.datasovnet"
NODES_FILE="$DATASOVNET_DIR/nodes.json"
MODELS_DIR="$DATASOVNET_DIR/models"
LLAMA_CPP_DIR="$DATASOVNET_DIR/llama.cpp"
LLAMA_SERVER="$LLAMA_CPP_DIR/build/bin/llama-server"
LLAMA_CLI="$LLAMA_CPP_DIR/build/bin/llama-cli"
INFERENCE_PORT=8080
INFERENCE_PID_FILE="$DATASOVNET_DIR/inference.pid"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ─── Worker Management ────────────────────────────────────

add_worker() {
  local name="$1"
  local ip="$2"
  local port="${3:-50052}"

  if [ -z "$name" ] || [ -z "$ip" ]; then
    echo "  Usage: coordinator.sh add-worker <name> <tailscale-ip> [rpc-port]"
    return 1
  fi

  mkdir -p "$DATASOVNET_DIR"

  if [ ! -f "$NODES_FILE" ]; then
    echo '[]' > "$NODES_FILE"
  fi

  # Test RPC connectivity (simple TCP check)
  echo -ne "  Testing RPC connection to ${name} (${ip}:${port})... "

  if nc -z -w 5 "$ip" "$port" 2>/dev/null; then
    echo -e "${GREEN}connected${NC}"
  else
    echo -e "${YELLOW}port not responding${NC}"
    echo -ne "  The RPC worker may not be running yet. Add anyway? [Y/n] "
    read -r ADD_ANYWAY
    if [[ "$ADD_ANYWAY" =~ ^[Nn] ]]; then
      return 1
    fi
  fi

  # Also check Ollama if available
  OLLAMA_STATUS="unknown"
  OLLAMA_MODELS="none"
  if curl -s --connect-timeout 3 "http://${ip}:11434/api/tags" &>/dev/null; then
    OLLAMA_STATUS="available"
    OLLAMA_MODELS=$(curl -s "http://${ip}:11434/api/tags" | python3 -c "
import sys, json
data = json.load(sys.stdin)
models = [m['name'] for m in data.get('models', [])]
print(', '.join(models) if models else 'none')
" 2>/dev/null || echo "unknown")
  fi

  python3 -c "
import json
from datetime import datetime

nodes_file = '$NODES_FILE'
try:
    with open(nodes_file) as f:
        nodes = json.load(f)
except:
    nodes = []

nodes = [n for n in nodes if n['name'] != '$name']

nodes.append({
    'name': '$name',
    'ip': '$ip',
    'rpc_port': $port,
    'rpc_endpoint': '${ip}:${port}',
    'ollama_status': '$OLLAMA_STATUS',
    'ollama_models': '$OLLAMA_MODELS'.split(', ') if '$OLLAMA_MODELS' != 'none' else [],
    'status': 'added',
    'added_at': datetime.utcnow().isoformat() + 'Z'
})

with open(nodes_file, 'w') as f:
    json.dump(nodes, f, indent=2)
"

  echo -e "  ${GREEN}+${NC} Worker '${name}' added (${ip}:${port})"
  if [ "$OLLAMA_MODELS" != "none" ]; then
    echo -e "  ${DIM}Ollama models on ${name}: ${OLLAMA_MODELS}${NC}"
  fi
}

remove_worker() {
  local name="$1"

  if [ ! -f "$NODES_FILE" ]; then
    echo "  No workers configured."
    return 1
  fi

  python3 -c "
import json
with open('$NODES_FILE') as f:
    nodes = json.load(f)
before = len(nodes)
nodes = [n for n in nodes if n['name'] != '$name']
with open('$NODES_FILE', 'w') as f:
    json.dump(nodes, f, indent=2)
if len(nodes) < before:
    print(f'  Removed worker: $name')
else:
    print(f'  Worker not found: $name')
"
}

list_workers() {
  echo ""
  echo -e "  ${BOLD}DataSovNet Network${NC}"
  echo "  ================================================"

  if [ ! -f "$NODES_FILE" ] || [ "$(cat "$NODES_FILE")" = "[]" ]; then
    echo "  No workers registered."
    echo ""
    echo "  Add a worker:  coordinator.sh add-worker <name> <tailscale-ip>"
    echo ""
    return
  fi

  python3 -c "
import json
with open('$NODES_FILE') as f:
    nodes = json.load(f)

print(f'  Workers: {len(nodes)}')
print()
for n in nodes:
    status = n.get('status', 'unknown')
    rpc = n.get('rpc_endpoint', f\"{n['ip']}:{n.get('rpc_port', 50052)}\")
    ollama = ', '.join(n.get('ollama_models', [])) or 'none'
    print(f'  {n[\"name\"]:15s}  rpc={rpc:22s}  status={status:8s}  ollama={ollama}')

print()
"
}

# ─── Health Check ─────────────────────────────────────────

check_health() {
  echo ""
  echo -e "  ${BOLD}Network Health Check${NC}"
  echo "  ================================================"

  if [ ! -f "$NODES_FILE" ]; then
    echo "  No workers configured."
    return
  fi

  python3 << 'PYEOF'
import json, socket, urllib.request, os

nodes_file = os.path.expanduser("~/.datasovnet/nodes.json")
with open(nodes_file) as f:
    nodes = json.load(f)

online = 0
offline = 0
total_vram = 0

for node in nodes:
    ip = node["ip"]
    rpc_port = node.get("rpc_port", 50052)
    name = node["name"]

    # Check RPC port
    rpc_ok = False
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        result = sock.connect_ex((ip, rpc_port))
        sock.close()
        rpc_ok = (result == 0)
    except:
        pass

    # Check Ollama
    ollama_ok = False
    ollama_models = []
    try:
        req = urllib.request.urlopen(f"http://{ip}:11434/api/tags", timeout=5)
        data = json.loads(req.read())
        ollama_models = [m["name"] for m in data.get("models", [])]
        ollama_ok = True
    except:
        pass

    if rpc_ok:
        node["status"] = "online"
        online += 1
        print(f"  \033[0;32m●\033[0m {name:15s} RPC=UP   ollama={'UP (' + ', '.join(ollama_models) + ')' if ollama_ok else 'down'}   {ip}:{rpc_port}")
    else:
        node["status"] = "offline"
        offline += 1
        print(f"  \033[0;31m●\033[0m {name:15s} RPC=DOWN ollama={'UP' if ollama_ok else 'down'}   {ip}:{rpc_port}")

    node["ollama_models"] = ollama_models

with open(nodes_file, "w") as f:
    json.dump(nodes, f, indent=2)

print()
print(f"  Online: {online}  Offline: {offline}  Total: {len(nodes)}")
print()
PYEOF
}

# ─── Model Management ────────────────────────────────────

download_model() {
  local model_alias="${1:-}"
  mkdir -p "$MODELS_DIR"

  echo ""
  echo -e "  ${BOLD}Download Model${NC}"
  echo "  ================================================"

  case "$model_alias" in
    deepseek-r1-70b|deepseek|ds70b)
      MODEL_NAME="DeepSeek-R1-Distill-Llama-70B-Q4_K_M"
      MODEL_URL="https://huggingface.co/bartowski/DeepSeek-R1-Distill-Llama-70B-GGUF/resolve/main/DeepSeek-R1-Distill-Llama-70B-Q4_K_M.gguf"
      MODEL_SIZE="~42GB"
      ;;
    deepseek-r1-8b|ds8b)
      MODEL_NAME="DeepSeek-R1-Distill-Llama-8B-Q4_K_M"
      MODEL_URL="https://huggingface.co/bartowski/DeepSeek-R1-Distill-Llama-8B-GGUF/resolve/main/DeepSeek-R1-Distill-Llama-8B-Q4_K_M.gguf"
      MODEL_SIZE="~5GB"
      ;;
    qwen3-30b|qwen)
      MODEL_NAME="Qwen3-30B-A3B-Q4_K_M"
      MODEL_URL="https://huggingface.co/bartowski/Qwen3-30B-A3B-GGUF/resolve/main/Qwen3-30B-A3B-Q4_K_M.gguf"
      MODEL_SIZE="~17GB"
      ;;
    llama-scout|scout)
      MODEL_NAME="Llama-4-Scout-17B-16E-Instruct-Q4_K_M"
      MODEL_URL="https://huggingface.co/bartowski/Llama-4-Scout-17B-16E-Instruct-GGUF/resolve/main/Llama-4-Scout-17B-16E-Instruct-Q4_K_M.gguf"
      MODEL_SIZE="~48GB"
      ;;
    "")
      echo "  Available models:"
      echo ""
      echo "    deepseek-r1-70b   DeepSeek R1 Distill 70B (Q4_K_M, ~42GB) [RECOMMENDED]"
      echo "    deepseek-r1-8b    DeepSeek R1 Distill 8B  (Q4_K_M, ~5GB)  [test model]"
      echo "    qwen3-30b         Qwen3 30B-A3B           (Q4_K_M, ~17GB) [fast MoE]"
      echo "    llama-scout       Llama 4 Scout 109B MoE  (Q4_K_M, ~48GB) [experimental]"
      echo ""
      echo "  Usage: coordinator.sh download-model <model>"
      echo ""
      echo "  Or provide a direct GGUF URL:"
      echo "    coordinator.sh download-model --url <huggingface-gguf-url>"
      return
      ;;
    --url)
      MODEL_URL="${2:-}"
      if [ -z "$MODEL_URL" ]; then
        echo "  Provide a URL: coordinator.sh download-model --url <url>"
        return 1
      fi
      MODEL_NAME=$(basename "$MODEL_URL")
      MODEL_SIZE="unknown"
      ;;
    *)
      echo "  Unknown model: $model_alias"
      echo "  Run without args to see available models."
      return 1
      ;;
  esac

  MODEL_FILE="$MODELS_DIR/$MODEL_NAME.gguf"

  if [ -f "$MODEL_FILE" ]; then
    echo -e "  ${GREEN}+${NC} Model already downloaded: $MODEL_FILE"
    return 0
  fi

  echo "  Downloading: $MODEL_NAME ($MODEL_SIZE)"
  echo "  This may take a while..."
  echo ""

  # Use curl with progress bar, resume support
  curl -L --progress-bar -C - -o "$MODEL_FILE.part" "$MODEL_URL"
  mv "$MODEL_FILE.part" "$MODEL_FILE"

  echo ""
  echo -e "  ${GREEN}+${NC} Model saved: $MODEL_FILE"
  echo -e "  ${GREEN}+${NC} Size: $(du -h "$MODEL_FILE" | awk '{print $1}')"
}

# ─── Distributed Inference ────────────────────────────────

get_rpc_endpoints() {
  if [ ! -f "$NODES_FILE" ]; then
    echo ""
    return
  fi
  python3 -c "
import json
with open('$NODES_FILE') as f:
    nodes = json.load(f)
endpoints = [n.get('rpc_endpoint', f\"{n['ip']}:{n.get('rpc_port', 50052)}\") for n in nodes]
print(','.join(endpoints))
"
}

start_inference() {
  local model_file="${1:-}"

  echo ""
  echo -e "  ${BOLD}Starting Distributed Inference${NC}"
  echo "  ================================================"

  # Find model file
  if [ -z "$model_file" ]; then
    # Look for models in models dir
    if [ -d "$MODELS_DIR" ]; then
      MODEL_FILES=$(ls "$MODELS_DIR"/*.gguf 2>/dev/null || true)
      if [ -z "$MODEL_FILES" ]; then
        echo "  No models found. Download one first:"
        echo "    coordinator.sh download-model deepseek-r1-70b"
        return 1
      fi

      echo "  Available models:"
      echo ""
      local i=1
      for f in $MODELS_DIR/*.gguf; do
        SIZE=$(du -h "$f" | awk '{print $1}')
        echo "    $i) $(basename "$f") ($SIZE)"
        i=$((i + 1))
      done
      echo ""
      echo -ne "  Select model [1]: "
      read -r MODEL_CHOICE
      MODEL_CHOICE="${MODEL_CHOICE:-1}"

      model_file=$(ls "$MODELS_DIR"/*.gguf | sed -n "${MODEL_CHOICE}p")
    else
      echo "  No models directory. Download a model first."
      return 1
    fi
  fi

  if [ ! -f "$model_file" ]; then
    echo "  Model file not found: $model_file"
    return 1
  fi

  echo -e "  Model: ${CYAN}$(basename "$model_file")${NC}"

  # Get RPC endpoints
  RPC_ENDPOINTS=$(get_rpc_endpoints)

  if [ -n "$RPC_ENDPOINTS" ]; then
    echo -e "  RPC Workers: ${CYAN}$RPC_ENDPOINTS${NC}"
    RPC_FLAG="--rpc $RPC_ENDPOINTS"
  else
    echo -e "  ${YELLOW}No RPC workers — running on local GPU only${NC}"
    RPC_FLAG=""
  fi

  # Kill existing inference server
  if [ -f "$INFERENCE_PID_FILE" ]; then
    OLD_PID=$(cat "$INFERENCE_PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
      echo "  Stopping existing inference server (PID $OLD_PID)..."
      kill "$OLD_PID" 2>/dev/null || true
      sleep 2
    fi
    rm -f "$INFERENCE_PID_FILE"
  fi

  echo ""
  echo "  Starting llama-server on port $INFERENCE_PORT..."
  echo ""

  # Launch llama-server with distributed RPC
  # shellcheck disable=SC2086
  "$LLAMA_SERVER" \
    --model "$model_file" \
    --port "$INFERENCE_PORT" \
    --host 0.0.0.0 \
    --ctx-size 8192 \
    --n-gpu-layers 999 \
    $RPC_FLAG \
    > "$DATASOVNET_DIR/inference.log" 2>&1 &

  INFERENCE_PID=$!
  echo "$INFERENCE_PID" > "$INFERENCE_PID_FILE"

  echo "  Server PID: $INFERENCE_PID"
  echo "  Log: $DATASOVNET_DIR/inference.log"
  echo ""

  # Wait for server to be ready
  echo -ne "  Waiting for server to load model"
  for i in $(seq 1 60); do
    if curl -s "http://localhost:$INFERENCE_PORT/health" 2>/dev/null | grep -q "ok"; then
      echo -e " ${GREEN}ready!${NC}"
      echo ""
      echo -e "  ${GREEN}${BOLD}Distributed inference is running!${NC}"
      echo ""
      echo "  API:       http://localhost:$INFERENCE_PORT"
      echo "  Chat:      coordinator.sh chat 'your prompt'"
      echo "  Stop:      coordinator.sh stop-inference"
      echo "  Dashboard: http://localhost:$INFERENCE_PORT (browser)"
      echo ""
      return 0
    fi
    echo -n "."
    sleep 3
  done

  echo -e " ${RED}timeout${NC}"
  echo ""
  echo "  Server may still be loading. Check:"
  echo "    tail -f $DATASOVNET_DIR/inference.log"
  echo ""
}

stop_inference() {
  if [ -f "$INFERENCE_PID_FILE" ]; then
    PID=$(cat "$INFERENCE_PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
      kill "$PID"
      rm -f "$INFERENCE_PID_FILE"
      echo "  Inference server stopped (PID $PID)"
    else
      rm -f "$INFERENCE_PID_FILE"
      echo "  Server was not running (stale PID file cleaned)"
    fi
  else
    # Try to find and kill any llama-server
    if pkill -f "llama-server" 2>/dev/null; then
      echo "  Inference server stopped"
    else
      echo "  No inference server running"
    fi
  fi
}

# ─── Chat Interface ──────────────────────────────────────

chat() {
  local prompt="$*"

  if [ -z "$prompt" ]; then
    echo ""
    echo -e "  ${BOLD}DataSovNet Chat${NC}"
    echo "  Type your message. Press Ctrl+C to exit."
    echo ""

    while true; do
      echo -ne "  ${CYAN}You:${NC} "
      read -r prompt
      if [ -z "$prompt" ]; then continue; fi

      echo ""
      echo -ne "  ${GREEN}AI:${NC} "
      curl -s "http://localhost:$INFERENCE_PORT/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d "{\"messages\": [{\"role\": \"user\", \"content\": \"$prompt\"}], \"stream\": false}" \
        | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data['choices'][0]['message']['content'])
except Exception as e:
    print(f'Error: {e}. Is the inference server running?')
" 2>/dev/null
      echo ""
    done
  fi

  # Single prompt mode
  curl -s "http://localhost:$INFERENCE_PORT/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "{\"messages\": [{\"role\": \"user\", \"content\": \"$prompt\"}], \"stream\": false}" \
    | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data['choices'][0]['message']['content'])
except Exception as e:
    print(f'Error: {e}. Is the inference server running? (coordinator.sh start-inference)')
" 2>/dev/null
}

# ─── Query via Ollama (single-node) ──────────────────────

query_ollama() {
  local node_name="$1"
  shift
  local prompt="$*"

  if [ ! -f "$NODES_FILE" ]; then
    echo "  No workers configured."
    return 1
  fi

  NODE_IP=$(python3 -c "
import json
with open('$NODES_FILE') as f:
    nodes = json.load(f)
for n in nodes:
    if n['name'] == '$node_name':
        print(n['ip'])
        break
")

  if [ -z "$NODE_IP" ]; then
    echo "  Worker '$node_name' not found."
    return 1
  fi

  MODEL=$(python3 -c "
import json
with open('$NODES_FILE') as f:
    nodes = json.load(f)
for n in nodes:
    if n['name'] == '$node_name':
        models = n.get('ollama_models', [])
        print(models[0] if models else 'llama3.2:1b')
        break
")

  echo -e "  Querying ${CYAN}${node_name}${NC} via Ollama (${MODEL})..."
  echo ""

  curl -s "http://${NODE_IP}:11434/api/generate" \
    -d "{\"model\": \"${MODEL}\", \"prompt\": \"${prompt}\", \"stream\": false}" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('response', 'No response'))
" 2>/dev/null
  echo ""
}

# ─── Network Status ──────────────────────────────────────

network_status() {
  echo ""
  echo -e "  ${BOLD}DataSovNet Status${NC}"
  echo "  ================================================"

  # Check coordinator
  echo ""
  echo -e "  ${BOLD}Coordinator (this machine):${NC}"
  if command -v tailscale &>/dev/null; then
    TS_IP=$(tailscale ip -4 2>/dev/null || echo "not connected")
    echo "    Tailscale: $TS_IP"
  else
    echo "    Tailscale: not installed"
  fi

  if [ -f "$INFERENCE_PID_FILE" ]; then
    PID=$(cat "$INFERENCE_PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
      echo -e "    Inference: ${GREEN}running${NC} (PID $PID, port $INFERENCE_PORT)"
    else
      echo -e "    Inference: ${RED}dead${NC} (stale PID)"
    fi
  else
    echo -e "    Inference: ${DIM}stopped${NC}"
  fi

  # Check workers
  echo ""
  echo -e "  ${BOLD}Workers:${NC}"
  check_health
}

# ─── Usage ───────────────────────────────────────────────

usage() {
  echo ""
  echo -e "  ${BOLD}DataSovNet Coordinator${NC}"
  echo ""
  echo -e "  ${BOLD}Worker Management:${NC}"
  echo "    add-worker <name> <ip> [port]   Add an RPC worker node"
  echo "    remove-worker <name>            Remove a worker"
  echo "    list                            List all workers"
  echo "    health                          Check all worker health"
  echo "    status                          Full network status"
  echo ""
  echo -e "  ${BOLD}Distributed Inference:${NC}"
  echo "    download-model [name]           Download a GGUF model"
  echo "    start-inference [model-file]    Start distributed llama-server"
  echo "    stop-inference                  Stop inference server"
  echo "    chat [prompt]                   Chat with the distributed model"
  echo ""
  echo -e "  ${BOLD}Ollama (single-node):${NC}"
  echo "    query-ollama <node> <prompt>    Query a specific node via Ollama"
  echo ""
  echo -e "  ${BOLD}Examples:${NC}"
  echo "    coordinator.sh add-worker marks-pc 100.64.1.5"
  echo "    coordinator.sh add-worker ernesto-4090 100.64.1.3"
  echo "    coordinator.sh health"
  echo "    coordinator.sh download-model deepseek-r1-70b"
  echo "    coordinator.sh start-inference"
  echo "    coordinator.sh chat 'What is data sovereignty?'"
  echo ""
}

# ─── Main ────────────────────────────────────────────────

case "${1:-}" in
  add-worker)       add_worker "${2:-}" "${3:-}" "${4:-50052}" ;;
  remove-worker)    remove_worker "${2:-}" ;;
  list)             list_workers ;;
  health)           check_health ;;
  status)           network_status ;;
  download-model)   shift; download_model "$@" ;;
  start-inference)  start_inference "${2:-}" ;;
  stop-inference)   stop_inference ;;
  chat)             shift; chat "$@" ;;
  query-ollama)     shift; query_ollama "$@" ;;
  *)                usage ;;
esac
