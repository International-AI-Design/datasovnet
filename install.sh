#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────
# DataSovNet Node Installer
# Installs llama.cpp with RPC for distributed AI inference
# + Tailscale for secure mesh networking
# ─────────────────────────────────────────────────────────

DATASOVNET_VERSION="0.2.0"
DATASOVNET_DIR="$HOME/.datasovnet"
CONFIG_FILE="$DATASOVNET_DIR/config.json"
LOG_FILE="$DATASOVNET_DIR/install.log"
LLAMA_CPP_DIR="$DATASOVNET_DIR/llama.cpp"
RPC_PORT=50052

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_banner() {
  echo ""
  echo -e "${CYAN}${BOLD}"
  echo "  ╔═══════════════════════════════════════╗"
  echo "  ║        DataSovNet Node Setup          ║"
  echo "  ║   Distributed AI Compute Network      ║"
  echo "  ║      llama.cpp RPC + Tailscale        ║"
  echo "  ╚═══════════════════════════════════════╝"
  echo -e "${NC}"
  echo "  Version: $DATASOVNET_VERSION"
  echo ""
}

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
  echo -e "  ${GREEN}+${NC} $1"
}

warn() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $1" >> "$LOG_FILE"
  echo -e "  ${YELLOW}!${NC} $1"
}

error() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE"
  echo -e "  ${RED}x${NC} $1"
}

# ─── System Detection ────────────────────────────────────

detect_system() {
  echo -e "\n  ${BOLD}Detecting system...${NC}\n"

  OS="unknown"
  ARCH="unknown"
  GPU_TYPE="none"
  GPU_VRAM="0"
  TOTAL_RAM="0"
  GPU_NAME=""
  CMAKE_GPU_FLAGS=""

  # OS
  case "$(uname -s)" in
    Darwin) OS="macos" ;;
    Linux)  OS="linux" ;;
    *)      error "Unsupported OS: $(uname -s). Windows users: run install-windows.ps1 instead."; exit 1 ;;
  esac

  # Architecture
  case "$(uname -m)" in
    arm64|aarch64) ARCH="arm64" ;;
    x86_64|amd64)  ARCH="x86_64" ;;
    *)             ARCH="$(uname -m)" ;;
  esac

  log "OS: $OS ($ARCH)"

  # RAM
  if [ "$OS" = "macos" ]; then
    TOTAL_RAM=$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0f", $1/1024/1024/1024}')
  else
    TOTAL_RAM=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || echo "0")
  fi
  log "System RAM: ${TOTAL_RAM}GB"

  # GPU Detection + CMAKE flags
  if [ "$OS" = "macos" ]; then
    if [ "$ARCH" = "arm64" ]; then
      GPU_TYPE="apple-silicon"
      GPU_VRAM="$TOTAL_RAM"
      GPU_NAME=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Apple Silicon")
      CMAKE_GPU_FLAGS="-DGGML_METAL=ON"
      log "GPU: Apple Silicon ($GPU_NAME, ${GPU_VRAM}GB unified memory)"
    else
      GPU_TYPE="intel-mac"
      GPU_VRAM="0"
      CMAKE_GPU_FLAGS=""
      warn "Intel Mac detected — CPU inference only (slow)"
    fi
  else
    # Linux — check for NVIDIA
    if command -v nvidia-smi &>/dev/null; then
      GPU_TYPE="nvidia"
      GPU_VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | awk '{printf "%.0f", $1/1024}')
      GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
      CMAKE_GPU_FLAGS="-DGGML_CUDA=ON"
      log "GPU: NVIDIA $GPU_NAME (${GPU_VRAM}GB VRAM)"
    elif command -v rocm-smi &>/dev/null; then
      GPU_TYPE="amd"
      GPU_VRAM=$(rocm-smi --showmeminfo vram 2>/dev/null | grep "Total" | awk '{printf "%.0f", $3/1024/1024/1024}')
      GPU_NAME="AMD ROCm GPU"
      CMAKE_GPU_FLAGS="-DGGML_HIP=ON"
      log "GPU: AMD ROCm (${GPU_VRAM}GB VRAM)"
    else
      GPU_TYPE="cpu-only"
      GPU_VRAM="0"
      GPU_NAME="CPU"
      CMAKE_GPU_FLAGS=""
      warn "No GPU detected — CPU-only inference (slower but still works as RPC worker)"
    fi
  fi

  # Compute available memory for model sizing
  AVAILABLE_MEM="$GPU_VRAM"
  if [ "$GPU_VRAM" = "0" ]; then
    AVAILABLE_MEM="$TOTAL_RAM"
  fi

  if [ "$AVAILABLE_MEM" -ge 32 ]; then
    MODEL_TIER="large"
    log "Tier: LARGE — can contribute 32GB+ to distributed models"
  elif [ "$AVAILABLE_MEM" -ge 16 ]; then
    MODEL_TIER="medium"
    log "Tier: MEDIUM — can contribute 16GB+ to distributed models"
  elif [ "$AVAILABLE_MEM" -ge 8 ]; then
    MODEL_TIER="small"
    log "Tier: SMALL — can contribute 8GB+ to distributed models"
  else
    MODEL_TIER="minimal"
    warn "Tier: MINIMAL — limited contribution but still useful"
  fi
}

# ─── Install Build Dependencies ──────────────────────────

install_build_deps() {
  echo -e "\n  ${BOLD}Installing build dependencies...${NC}\n"

  if [ "$OS" = "macos" ]; then
    # Xcode command line tools (includes cmake, git, clang)
    if ! command -v cmake &>/dev/null; then
      if command -v brew &>/dev/null; then
        brew install cmake 2>>"$LOG_FILE"
      else
        error "CMake not found. Install Xcode Command Line Tools: xcode-select --install"
        error "Or install Homebrew and re-run: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
      fi
    fi
    log "CMake available"

    if ! command -v git &>/dev/null; then
      error "Git not found. Install: xcode-select --install"
      exit 1
    fi
    log "Git available"

  elif [ "$OS" = "linux" ]; then
    # Detect package manager
    if command -v apt-get &>/dev/null; then
      sudo apt-get update -qq 2>>"$LOG_FILE"
      sudo apt-get install -y -qq build-essential cmake git 2>>"$LOG_FILE"
    elif command -v dnf &>/dev/null; then
      sudo dnf install -y gcc gcc-c++ cmake git 2>>"$LOG_FILE"
    elif command -v pacman &>/dev/null; then
      sudo pacman -S --noconfirm base-devel cmake git 2>>"$LOG_FILE"
    else
      error "Unknown package manager. Install cmake, git, and a C++ compiler manually."
      exit 1
    fi
    log "Build tools installed (cmake, git, C++ compiler)"

    # NVIDIA: check for CUDA toolkit
    if [ "$GPU_TYPE" = "nvidia" ]; then
      if ! command -v nvcc &>/dev/null; then
        warn "CUDA toolkit not found. Checking for toolkit..."
        if [ -d "/usr/local/cuda" ]; then
          export PATH="/usr/local/cuda/bin:$PATH"
          export LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"
          log "Found CUDA at /usr/local/cuda"
        else
          error "CUDA toolkit required for NVIDIA GPU support."
          echo ""
          echo "  Install CUDA:"
          echo "    Ubuntu/Debian: sudo apt install nvidia-cuda-toolkit"
          echo "    Or download from: https://developer.nvidia.com/cuda-downloads"
          echo ""
          echo -ne "  Continue without CUDA (CPU-only)? [y/N] "
          read -r SKIP_CUDA
          if [[ "$SKIP_CUDA" =~ ^[Yy] ]]; then
            CMAKE_GPU_FLAGS=""
            GPU_TYPE="cpu-only"
            warn "Continuing without CUDA — GPU will not be used"
          else
            exit 1
          fi
        fi
      else
        log "CUDA toolkit available ($(nvcc --version | grep release | awk '{print $5}' | tr -d ','))"
      fi
    fi
  fi
}

# ─── Build llama.cpp with RPC ────────────────────────────

build_llama_cpp() {
  echo -e "\n  ${BOLD}Building llama.cpp with RPC support...${NC}\n"

  if [ -f "$LLAMA_CPP_DIR/build/bin/rpc-server" ] && [ -f "$LLAMA_CPP_DIR/build/bin/llama-server" ]; then
    log "llama.cpp already built"
    echo -ne "  Rebuild from source? [y/N] "
    read -r REBUILD
    if [[ ! "$REBUILD" =~ ^[Yy] ]]; then
      return 0
    fi
  fi

  mkdir -p "$DATASOVNET_DIR"

  # Clone or update llama.cpp
  if [ -d "$LLAMA_CPP_DIR" ]; then
    echo "  Updating llama.cpp..."
    cd "$LLAMA_CPP_DIR"
    git pull --quiet 2>>"$LOG_FILE"
  else
    echo "  Cloning llama.cpp..."
    git clone https://github.com/ggerganov/llama.cpp.git "$LLAMA_CPP_DIR" 2>>"$LOG_FILE"
    cd "$LLAMA_CPP_DIR"
  fi

  log "Source ready at $LLAMA_CPP_DIR"

  # Build with RPC enabled + GPU acceleration
  echo "  Building with flags: -DGGML_RPC=ON $CMAKE_GPU_FLAGS"
  echo "  (This takes a few minutes on first build...)"
  echo ""

  cmake -B build \
    -DGGML_RPC=ON \
    $CMAKE_GPU_FLAGS \
    -DCMAKE_BUILD_TYPE=Release \
    2>>"$LOG_FILE"

  cmake --build build --config Release -j "$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)" \
    2>>"$LOG_FILE"

  # Verify binaries
  if [ -f "build/bin/rpc-server" ]; then
    log "rpc-server built successfully"
  else
    error "rpc-server binary not found after build"
    exit 1
  fi

  if [ -f "build/bin/llama-server" ]; then
    log "llama-server built successfully"
  else
    error "llama-server binary not found after build"
    exit 1
  fi

  if [ -f "build/bin/llama-cli" ]; then
    log "llama-cli built successfully"
  fi

  # Create symlinks in a PATH-accessible location
  mkdir -p "$HOME/.local/bin"
  ln -sf "$LLAMA_CPP_DIR/build/bin/rpc-server" "$HOME/.local/bin/datasov-rpc-server"
  ln -sf "$LLAMA_CPP_DIR/build/bin/llama-server" "$HOME/.local/bin/datasov-llama-server"
  ln -sf "$LLAMA_CPP_DIR/build/bin/llama-cli" "$HOME/.local/bin/datasov-llama-cli"

  # Add to PATH if not already there
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    SHELL_RC="$HOME/.bashrc"
    if [ -f "$HOME/.zshrc" ]; then
      SHELL_RC="$HOME/.zshrc"
    fi
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
    export PATH="$HOME/.local/bin:$PATH"
    log "Added ~/.local/bin to PATH in $SHELL_RC"
  fi

  log "Binaries linked: datasov-rpc-server, datasov-llama-server, datasov-llama-cli"
}

# ─── Install Tailscale ───────────────────────────────────

install_tailscale() {
  echo -e "\n  ${BOLD}Installing Tailscale (mesh VPN)...${NC}\n"

  if command -v tailscale &>/dev/null; then
    log "Tailscale already installed"

    # Check if connected
    if tailscale status &>/dev/null 2>&1; then
      TS_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
      log "Tailscale connected: $TS_IP"
    else
      warn "Tailscale installed but not connected. Run: tailscale up"
    fi
    return 0
  fi

  if [ "$OS" = "macos" ]; then
    if command -v brew &>/dev/null; then
      brew install --cask tailscale 2>>"$LOG_FILE"
    else
      echo -e "  ${YELLOW}Install Tailscale from: https://tailscale.com/download/mac${NC}"
      echo "  (It's a free app from the Mac App Store or the website)"
      echo -ne "  Press Enter after installing... "
      read -r
    fi
  else
    curl -fsSL https://tailscale.com/install.sh | sh 2>>"$LOG_FILE"
  fi

  if command -v tailscale &>/dev/null; then
    log "Tailscale installed"
    echo ""
    echo -e "  ${BOLD}Connect to Tailscale now:${NC}"
    echo "    sudo tailscale up"
    echo ""
    echo -ne "  Press Enter after connecting (or skip for later)... "
    read -r
  else
    warn "Tailscale may need manual setup. Visit: https://tailscale.com/download"
  fi
}

# ─── Install Ollama (for single-node inference) ──────────

install_ollama() {
  echo -e "\n  ${BOLD}Installing Ollama (for local single-node inference)...${NC}\n"

  if command -v ollama &>/dev/null; then
    log "Ollama already installed"
    return 0
  fi

  echo -ne "  Install Ollama for local inference? [Y/n] "
  read -r INSTALL_OLLAMA
  if [[ "$INSTALL_OLLAMA" =~ ^[Nn] ]]; then
    warn "Skipping Ollama — node will only serve as RPC worker"
    return 0
  fi

  if [ "$OS" = "macos" ]; then
    if command -v brew &>/dev/null; then
      brew install ollama 2>>"$LOG_FILE"
    else
      curl -fsSL https://ollama.com/install.sh | sh 2>>"$LOG_FILE"
    fi
  else
    curl -fsSL https://ollama.com/install.sh | sh 2>>"$LOG_FILE"
  fi

  if command -v ollama &>/dev/null; then
    log "Ollama installed"
  else
    warn "Ollama install failed — not critical, RPC still works"
  fi
}

# ─── Configure Node ──────────────────────────────────────

configure_node() {
  echo -e "\n  ${BOLD}Configuring DataSovNet node...${NC}\n"

  # Get node name
  DEFAULT_NAME=$(hostname -s 2>/dev/null || echo "node-$(date +%s)")
  echo -ne "  Node name [${DEFAULT_NAME}]: "
  read -r NODE_NAME
  NODE_NAME="${NODE_NAME:-$DEFAULT_NAME}"

  # Determine role
  echo ""
  echo "  Node roles:"
  echo "    1) RPC Worker  — Contributes GPU to the distributed network (most nodes)"
  echo "    2) Coordinator — Loads models and distributes across workers (usually 1 per network)"
  echo ""
  echo -ne "  Role [1]: "
  read -r ROLE_CHOICE
  if [ "$ROLE_CHOICE" = "2" ]; then
    NODE_ROLE="coordinator"
  else
    NODE_ROLE="worker"
  fi

  # Get coordinator address (workers need this)
  COORDINATOR_IP="self"
  if [ "$NODE_ROLE" = "worker" ]; then
    echo -ne "  Coordinator's Tailscale IP: "
    read -r COORDINATOR_IP
    if [ -z "$COORDINATOR_IP" ]; then
      warn "No coordinator IP — you can set this later in $CONFIG_FILE"
      COORDINATOR_IP="unknown"
    fi
  fi

  # Get Tailscale IP
  TS_IP="unknown"
  if command -v tailscale &>/dev/null; then
    TS_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
  fi

  # Generate node ID
  NODE_ID="dsn-$(echo "$NODE_NAME-$(date +%s)" | shasum | cut -c1-8)"

  # Write config
  mkdir -p "$DATASOVNET_DIR"
  cat > "$CONFIG_FILE" << EOF
{
  "version": "$DATASOVNET_VERSION",
  "node_id": "$NODE_ID",
  "node_name": "$NODE_NAME",
  "role": "$NODE_ROLE",
  "coordinator_ip": "$COORDINATOR_IP",
  "tailscale_ip": "$TS_IP",
  "system": {
    "os": "$OS",
    "arch": "$ARCH",
    "gpu_type": "$GPU_TYPE",
    "gpu_name": "$GPU_NAME",
    "gpu_vram_gb": $GPU_VRAM,
    "total_ram_gb": $TOTAL_RAM,
    "model_tier": "$MODEL_TIER"
  },
  "rpc": {
    "port": $RPC_PORT,
    "host": "0.0.0.0"
  },
  "llama_cpp": {
    "dir": "$LLAMA_CPP_DIR",
    "rpc_server": "$LLAMA_CPP_DIR/build/bin/rpc-server",
    "llama_server": "$LLAMA_CPP_DIR/build/bin/llama-server",
    "llama_cli": "$LLAMA_CPP_DIR/build/bin/llama-cli"
  },
  "registered_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

  log "Node configured: $NODE_NAME ($NODE_ID) as $NODE_ROLE"
  log "Config saved to $CONFIG_FILE"
}

# ─── Create Systemd Service / LaunchAgent ─────────────────

create_service() {
  echo -e "\n  ${BOLD}Setting up RPC worker service...${NC}\n"

  if [ "$NODE_ROLE" = "coordinator" ]; then
    log "Coordinator node — skipping RPC worker service"
    return 0
  fi

  RPC_SERVER="$LLAMA_CPP_DIR/build/bin/rpc-server"

  if [ "$OS" = "linux" ]; then
    # Create systemd service
    sudo tee /etc/systemd/system/datasovnet-rpc.service > /dev/null << EOF
[Unit]
Description=DataSovNet RPC Worker
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=$RPC_SERVER --host 0.0.0.0 --port $RPC_PORT
Restart=always
RestartSec=5
User=$USER
Environment="CUDA_VISIBLE_DEVICES=0"

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable datasovnet-rpc 2>>"$LOG_FILE"
    log "Systemd service created: datasovnet-rpc"
    echo ""
    echo -ne "  Start RPC worker now? [Y/n] "
    read -r START_NOW
    if [[ ! "$START_NOW" =~ ^[Nn] ]]; then
      sudo systemctl start datasovnet-rpc
      sleep 2
      if sudo systemctl is-active --quiet datasovnet-rpc; then
        log "RPC worker running on port $RPC_PORT"
      else
        warn "RPC worker failed to start. Check: sudo journalctl -u datasovnet-rpc"
      fi
    fi

  elif [ "$OS" = "macos" ]; then
    # Create launchd plist
    PLIST_PATH="$HOME/Library/LaunchAgents/net.datasov.rpc-worker.plist"
    cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>net.datasov.rpc-worker</string>
    <key>ProgramArguments</key>
    <array>
        <string>$RPC_SERVER</string>
        <string>--host</string>
        <string>0.0.0.0</string>
        <string>--port</string>
        <string>$RPC_PORT</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$DATASOVNET_DIR/rpc-worker.log</string>
    <key>StandardErrorPath</key>
    <string>$DATASOVNET_DIR/rpc-worker.err</string>
</dict>
</plist>
EOF

    log "LaunchAgent created at $PLIST_PATH"
    echo ""
    echo -ne "  Start RPC worker now? [Y/n] "
    read -r START_NOW
    if [[ ! "$START_NOW" =~ ^[Nn] ]]; then
      launchctl load "$PLIST_PATH" 2>>"$LOG_FILE" || true
      sleep 2
      if launchctl list | grep -q "net.datasov.rpc-worker"; then
        log "RPC worker running on port $RPC_PORT"
      else
        warn "RPC worker may not have started. Check: cat $DATASOVNET_DIR/rpc-worker.log"
      fi
    fi
  fi
}

# ─── Quick Start Script ──────────────────────────────────

create_quick_scripts() {
  echo -e "\n  ${BOLD}Creating helper scripts...${NC}\n"

  # Start RPC worker manually
  cat > "$DATASOVNET_DIR/start-worker.sh" << 'SCRIPT'
#!/usr/bin/env bash
CONFIG="$HOME/.datasovnet/config.json"
RPC_SERVER=$(python3 -c "import json; print(json.load(open('$CONFIG'))['llama_cpp']['rpc_server'])")
PORT=$(python3 -c "import json; print(json.load(open('$CONFIG'))['rpc']['port'])")
echo "Starting RPC worker on 0.0.0.0:$PORT ..."
exec "$RPC_SERVER" --host 0.0.0.0 --port "$PORT"
SCRIPT
  chmod +x "$DATASOVNET_DIR/start-worker.sh"
  log "Created: $DATASOVNET_DIR/start-worker.sh"

  # Stop RPC worker
  cat > "$DATASOVNET_DIR/stop-worker.sh" << 'SCRIPT'
#!/usr/bin/env bash
pkill -f "rpc-server" && echo "RPC worker stopped." || echo "No RPC worker running."
SCRIPT
  chmod +x "$DATASOVNET_DIR/stop-worker.sh"
  log "Created: $DATASOVNET_DIR/stop-worker.sh"

  # Check status
  cat > "$DATASOVNET_DIR/status.sh" << 'SCRIPT'
#!/usr/bin/env bash
CONFIG="$HOME/.datasovnet/config.json"
echo ""
echo "  DataSovNet Node Status"
echo "  ======================"

if [ -f "$CONFIG" ]; then
  python3 -c "
import json
c = json.load(open('$CONFIG'))
print(f\"  Name:     {c['node_name']}\")
print(f\"  Role:     {c['role']}\")
print(f\"  GPU:      {c['system']['gpu_name']} ({c['system']['gpu_vram_gb']}GB)\")
print(f\"  Tier:     {c['system']['model_tier']}\")
print(f\"  TS IP:    {c.get('tailscale_ip', 'unknown')}\")
print(f\"  RPC Port: {c['rpc']['port']}\")
"
else
  echo "  Not configured. Run install.sh first."
fi

echo ""
if pgrep -f "rpc-server" > /dev/null 2>&1; then
  echo "  RPC Worker: RUNNING"
else
  echo "  RPC Worker: STOPPED"
fi

if command -v tailscale &>/dev/null; then
  TS_STATUS=$(tailscale status --json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('BackendState','unknown'))" 2>/dev/null || echo "unknown")
  TS_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
  echo "  Tailscale:  $TS_STATUS ($TS_IP)"
else
  echo "  Tailscale:  NOT INSTALLED"
fi
echo ""
SCRIPT
  chmod +x "$DATASOVNET_DIR/status.sh"
  log "Created: $DATASOVNET_DIR/status.sh"
}

# ─── Summary ─────────────────────────────────────────────

print_summary() {
  echo ""
  echo -e "  ${GREEN}${BOLD}=========================================${NC}"
  echo -e "  ${GREEN}${BOLD}  DataSovNet Node Setup Complete!${NC}"
  echo -e "  ${GREEN}${BOLD}=========================================${NC}"
  echo ""
  echo -e "  Node Name:   ${BOLD}$NODE_NAME${NC}"
  echo -e "  Node ID:     $NODE_ID"
  echo -e "  Role:        ${BOLD}$NODE_ROLE${NC}"
  echo -e "  GPU:         $GPU_NAME (${GPU_VRAM}GB)"
  echo -e "  Model Tier:  $MODEL_TIER"
  echo -e "  RPC Port:    $RPC_PORT"
  echo -e "  Config:      $CONFIG_FILE"

  # Get Tailscale IP
  TS_IP="not connected"
  if command -v tailscale &>/dev/null; then
    TS_IP=$(tailscale ip -4 2>/dev/null || echo "not connected")
  fi

  echo ""
  if [ "$TS_IP" != "not connected" ]; then
    echo -e "  ${CYAN}${BOLD}Tailscale IP: $TS_IP${NC}"
    echo -e "  ${CYAN}${BOLD}RPC endpoint: $TS_IP:$RPC_PORT${NC}"
  else
    echo -e "  ${YELLOW}Tailscale not connected yet. Run: sudo tailscale up${NC}"
  fi

  echo ""
  echo -e "  ${BOLD}Quick Commands:${NC}"
  echo ""
  echo "    ~/.datasovnet/start-worker.sh   # Start RPC worker"
  echo "    ~/.datasovnet/stop-worker.sh    # Stop RPC worker"
  echo "    ~/.datasovnet/status.sh         # Check node status"
  echo ""

  if [ "$NODE_ROLE" = "worker" ]; then
    echo -e "  ${BOLD}Tell the coordinator:${NC}"
    echo "    Node name:  $NODE_NAME"
    echo "    Tailscale:  $TS_IP"
    echo "    RPC port:   $RPC_PORT"
    echo ""
    echo "  The coordinator will run:"
    echo "    coordinator.sh add-worker $NODE_NAME $TS_IP $RPC_PORT"
    echo ""
  elif [ "$NODE_ROLE" = "coordinator" ]; then
    echo -e "  ${BOLD}To start distributed inference:${NC}"
    echo ""
    echo "  1. Add workers:    coordinator.sh add-worker <name> <tailscale-ip> [port]"
    echo "  2. Check workers:  coordinator.sh health"
    echo "  3. Download model: coordinator.sh download-model deepseek-r1-70b"
    echo "  4. Start server:   coordinator.sh start-inference"
    echo "  5. Chat:           coordinator.sh chat 'Your prompt here'"
    echo ""
  fi
}

# ─── Main ────────────────────────────────────────────────

main() {
  print_banner

  mkdir -p "$DATASOVNET_DIR"
  touch "$LOG_FILE"

  echo -e "  ${BOLD}This script will:${NC}"
  echo "  1. Detect your system hardware (GPU, RAM)"
  echo "  2. Install build tools (cmake, git)"
  echo "  3. Build llama.cpp with RPC support (distributed inference)"
  echo "  4. Install Tailscale (secure mesh VPN)"
  echo "  5. Optionally install Ollama (local single-node inference)"
  echo "  6. Configure your node and create helper scripts"
  echo ""
  echo -ne "  Continue? [Y/n] "
  read -r CONFIRM
  if [[ "$CONFIRM" =~ ^[Nn] ]]; then
    echo "  Cancelled."
    exit 0
  fi

  detect_system
  install_build_deps
  build_llama_cpp
  install_tailscale
  install_ollama
  configure_node
  create_service
  create_quick_scripts
  print_summary
}

main "$@"
