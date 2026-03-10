# DataSovNet — Distributed AI Compute Network

A distributed AI inference network using llama.cpp RPC. Connect multiple machines to run large language models (70B+) that no single machine could handle alone.

## How It Works

```
┌──────────────────────────────────────────────────────┐
│            Coordinator (Johnny's M3 Max)             │
│                                                      │
│  Loads model file, runs llama-server,                │
│  distributes layers to RPC workers                   │
│  proportional to available GPU memory                │
└──────────┬───────────────────────┬───────────────────┘
           │ Tailscale VPN         │
    ┌──────┴──────┐         ┌──────┴──────┐
    │ RPC Worker  │         │ RPC Worker  │
    │ RTX 4090    │         │ Gaming PC   │
    │ 24GB VRAM   │         │ ~24GB VRAM  │
    │             │         │             │
    │ rpc-server  │         │ rpc-server  │
    │ :50052      │         │ :50052      │
    └─────────────┘         └─────────────┘
```

Model file stays on the coordinator. Workers only provide raw GPU compute. All traffic encrypted via Tailscale (WireGuard).

## Quick Start

### Worker Nodes (Linux/macOS)
```bash
curl -fsSL https://raw.githubusercontent.com/International-AI-Design/datasovnet/main/install.sh | bash
```

### Worker Nodes (Windows)
```powershell
# In PowerShell as Administrator:
Set-ExecutionPolicy Bypass -Scope Process
.\install-windows.ps1
```

### Coordinator Setup
```bash
# Run install.sh and choose role: Coordinator
./install.sh

# Add workers
coordinator.sh add-worker marks-pc 100.64.1.5
coordinator.sh add-worker ernesto-4090 100.64.1.3

# Download a model
coordinator.sh download-model deepseek-r1-70b

# Start distributed inference
coordinator.sh start-inference

# Chat
coordinator.sh chat "What is data sovereignty?"
```

## What Gets Installed

1. **llama.cpp** — Built from source with RPC + GPU acceleration (Metal/CUDA/ROCm)
2. **Tailscale** — Zero-config mesh VPN (free, encrypted, NAT traversal)
3. **Ollama** (optional) — For single-node local inference
4. **Helper scripts** — start-worker, stop-worker, status

## Requirements

- **Workers:** Any machine with a GPU (NVIDIA, AMD, Apple Silicon) or just a CPU
- **Coordinator:** Machine with enough disk for model files (~42GB for 70B Q4)
- **Network:** Internet connection (Tailscale handles NAT/firewalls)

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

- All traffic encrypted via Tailscale (WireGuard-based)
- No ports exposed to the public internet
- Workers only accept RPC connections from the Tailscale mesh
- Model files stay on the coordinator — workers never see raw weights
