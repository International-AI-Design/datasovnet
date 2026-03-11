# DataSovNet — Distributed AI Compute Network

A distributed AI inference network using llama.cpp RPC. Connect multiple machines to run large language models (70B+) that no single machine could handle alone.

## Roadmap

### Phase 1: Home Network (ACTIVE)
Get three home machines running distributed inference over the local LAN (192.168.50.x):

| Node | Hardware | GPU Memory | Role | Status |
|------|----------|-----------|------|--------|
| Johnny's Mac | M3 Max | 36GB unified | Coordinator | Ready |
| Ernesto's PC | RTX 4090 | 24GB VRAM | RPC Worker | Setting up |
| Linux Server | GTX 1080 | 8GB VRAM | RPC Worker | Pending |

**Total: 68GB** — DeepSeek-R1-70B (39.6GB) with 28GB headroom for context.

No external network exposure. Direct LAN IPs. Security-first.

### Phase 2: Tailscale Mesh
Install Tailscale on all three home machines. Validate encrypted mesh VPN works alongside LAN. Security review with Ernesto before proceeding.

### Phase 3: External Nodes
Add Mark's gaming PC (remote location) via Tailscale. First true multi-site distributed inference. Then scale to additional nodes.

## How It Works

```
┌──────────────────────────────────────────────────────┐
│            Coordinator (Johnny's M3 Max)             │
│              192.168.50.71 (LAN)                     │
│  Loads model file, runs llama-server,                │
│  distributes layers to RPC workers                   │
│  proportional to available GPU memory                │
└──────────┬───────────────────────┬───────────────────┘
           │ LAN / Tailscale       │
    ┌──────┴──────┐         ┌──────┴──────┐
    │ RPC Worker  │         │ RPC Worker  │
    │ RTX 4090    │         │ GTX 1080    │
    │ 24GB VRAM   │         │ 8GB VRAM    │
    │ Ernesto's   │         │ Linux Srv   │
    │ rpc-server  │         │ rpc-server  │
    │ :50052      │         │ :50052      │
    └─────────────┘         └─────────────┘
```

Model file stays on the coordinator. Workers only provide raw GPU compute. For LAN deployment, traffic stays on the local network. Tailscale adds WireGuard encryption for cross-site connections.

## Quick Start

### Phase 1: LAN Setup (No Tailscale Required)

**On each worker (Linux):**
```bash
# Clone and install
git clone https://github.com/International-AI-Design/datasovnet.git
cd datasovnet && chmod +x install.sh && ./install.sh
# Choose role: Worker
# Coordinator IP: 192.168.50.71
```

**On each worker (Windows — PowerShell as Admin):**
```powershell
Set-ExecutionPolicy Bypass -Scope Process
.\install-windows.ps1
```

**On the coordinator (Johnny's Mac):**
```bash
# Add workers using LAN IPs
bash scripts/coordinator.sh add-worker ernesto-4090 192.168.50.X 50052
bash scripts/coordinator.sh add-worker linux-server 192.168.50.111 50052

# Verify connections
bash scripts/coordinator.sh health

# Start distributed inference
bash scripts/coordinator.sh start-inference

# Chat with the 70B model running across 3 machines
bash scripts/coordinator.sh chat "What is data sovereignty?"
```

### Phase 2+: Tailscale Setup
```bash
# Install Tailscale on all machines
# Linux: curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up
# macOS: brew install --cask tailscale
# Windows: winget install Tailscale.Tailscale

# Switch coordinator to use Tailscale IPs (100.x.y.z)
bash scripts/coordinator.sh add-worker ernesto-4090 100.x.y.z 50052
```

## What Gets Installed

1. **llama.cpp** — Built from source with RPC + GPU acceleration (Metal/CUDA/ROCm)
2. **Tailscale** (optional for LAN, required for cross-site) — Zero-config mesh VPN
3. **Helper scripts** — start-worker, stop-worker, status

## Requirements

- **Workers:** Any machine with a GPU (NVIDIA, AMD, Apple Silicon) or just a CPU
- **Coordinator:** Machine with enough disk for model files (~42GB for 70B Q4)
- **Network:** LAN for Phase 1, internet for Tailscale in Phase 2+

## Coordinator Commands

| Command | Description |
|---------|-------------|
| `add-worker <name> <ip> [port]` | Register an RPC worker |
| `remove-worker <name>` | Remove a worker |
| `list` | List all workers |
| `health` | Check worker connectivity |
| `status` | Full network status |
| `download-model [name]` | Download a GGUF model |
| `start-inference [file]` | Start distributed llama-server |
| `stop-inference` | Stop inference server |
| `chat [prompt]` | Chat with the distributed model |

## Available Models

| Alias | Model | Size | Notes |
|-------|-------|------|-------|
| `deepseek-r1-70b` | DeepSeek R1 Distill 70B Q4_K_M | ~42GB | Best reasoning, recommended |
| `deepseek-r1-8b` | DeepSeek R1 Distill 8B Q4_K_M | ~5GB | Quick testing |
| `qwen3-30b` | Qwen3 30B-A3B Q4_K_M | ~17GB | Fast MoE architecture |
| `llama-scout` | Llama 4 Scout 109B MoE Q4_K_M | ~48GB | Experimental |

## Security

- **Phase 1 (LAN):** Traffic stays on local network. No external exposure. Direct IP connections.
- **Phase 2+ (Tailscale):** All traffic encrypted via WireGuard. No ports exposed to the public internet. Workers only accept RPC connections from the mesh.
- Model files stay on the coordinator — workers never see raw weights.
