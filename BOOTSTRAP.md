# DataSovNet Worker Bootstrap — For Claude Code on a Fresh Machine

> **Context:** You are Claude Code, opened on a machine that needs to join the DataSovNet distributed compute network as an RPC worker. Johnny Ferro (the user) logged into his Claude Code account on this machine to set it up remotely.

## What You're Doing

This machine will become an **RPC worker** in a distributed AI inference network. It contributes its GPU to a pool so a coordinator node (Johnny's M3 Max) can run 70B+ parameter models across multiple machines using llama.cpp RPC.

**You do NOT need the model file.** The coordinator loads it. This machine just exposes GPU compute.

## Step-by-Step Setup

### 1. Detect the Environment

Run these commands to understand what you're working with:

```bash
# OS and architecture
uname -a

# GPU detection
nvidia-smi 2>/dev/null || echo "No NVIDIA GPU"
rocm-smi 2>/dev/null || echo "No AMD GPU"

# Check what's already installed
command -v git && git --version
command -v cmake && cmake --version
command -v tailscale && tailscale version
command -v ollama && ollama --version
```

Report the findings to Johnny before proceeding.

### 2. Install Tailscale

**Linux:**
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
tailscale ip -4  # Note this IP — the coordinator needs it
```

**Windows (PowerShell as Admin):**
```powershell
winget install Tailscale.Tailscale --accept-source-agreements --accept-package-agreements
# Then: Open Tailscale from Start Menu, sign in with Johnny's account
# After connecting:
tailscale ip -4  # Note this IP
```

**Johnny must approve the device on his Tailscale admin panel or use the same account.**

### 3. Install Build Dependencies

**Linux (Ubuntu/Debian):**
```bash
sudo apt-get update
sudo apt-get install -y build-essential cmake git
# For NVIDIA GPU:
sudo apt-get install -y nvidia-cuda-toolkit
```

**Linux (Fedora/RHEL):**
```bash
sudo dnf install -y gcc gcc-c++ cmake git
# For NVIDIA: install CUDA toolkit from NVIDIA website
```

**Windows:**
```powershell
winget install Git.Git --accept-source-agreements --accept-package-agreements
winget install Kitware.CMake --accept-source-agreements --accept-package-agreements
winget install Microsoft.VisualStudio.2022.BuildTools --accept-source-agreements --accept-package-agreements
# IMPORTANT: After VS Build Tools install, open Visual Studio Installer
# and add "Desktop Development with C++" workload
# CUDA: download from https://developer.nvidia.com/cuda-downloads
```

### 4. Build llama.cpp with RPC

**Linux/macOS:**
```bash
mkdir -p ~/.datasovnet
cd ~/.datasovnet
git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp

# Build with RPC + GPU
# For NVIDIA:
cmake -B build -DGGML_RPC=ON -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release
# For Apple Silicon:
cmake -B build -DGGML_RPC=ON -DGGML_METAL=ON -DCMAKE_BUILD_TYPE=Release
# For CPU only:
cmake -B build -DGGML_RPC=ON -DCMAKE_BUILD_TYPE=Release

cmake --build build --config Release -j $(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# Verify
ls -la build/bin/rpc-server
```

**Windows (Developer Command Prompt or PowerShell):**
```powershell
mkdir $env:USERPROFILE\.datasovnet -Force
cd $env:USERPROFILE\.datasovnet
git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp

cmake -B build -DGGML_RPC=ON -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release

# Binary will be at: build\bin\Release\rpc-server.exe
dir build\bin\Release\rpc-server.exe
```

### 5. Start the RPC Worker

**Linux/macOS:**
```bash
# Start in foreground (for testing):
~/.datasovnet/llama.cpp/build/bin/rpc-server --host 0.0.0.0 --port 50052

# Or background:
nohup ~/.datasovnet/llama.cpp/build/bin/rpc-server --host 0.0.0.0 --port 50052 > ~/.datasovnet/rpc-worker.log 2>&1 &
echo $! > ~/.datasovnet/rpc-worker.pid
```

**Windows:**
```powershell
# Start (leave this terminal open):
& "$env:USERPROFILE\.datasovnet\llama.cpp\build\bin\Release\rpc-server.exe" --host 0.0.0.0 --port 50052
```

### 6. Verify and Report

```bash
# Get Tailscale IP
tailscale ip -4

# Test that port 50052 is listening
# Linux: ss -tlnp | grep 50052
# Windows: netstat -an | findstr 50052
```

**Tell Johnny:**
- Tailscale IP: `<the IP>`
- GPU: `<name and VRAM>`
- RPC server: running on port 50052
- Status: ready for coordinator to connect

### 7. Windows Firewall (if needed)

```powershell
# Allow RPC port through Windows Firewall
New-NetFirewallRule -DisplayName "DataSovNet RPC" -Direction Inbound -Protocol TCP -LocalPort 50052 -Action Allow
```

## What Success Looks Like

- `rpc-server` is running and listening on 0.0.0.0:50052
- Tailscale is connected (has a 100.x.y.z IP)
- The coordinator can reach this machine's Tailscale IP on port 50052
- GPU memory is available for the coordinator to distribute model layers into

## Troubleshooting

- **CUDA not found during cmake:** Make sure CUDA toolkit (not just driver) is installed. `nvcc --version` should work.
- **Build fails on Windows:** Use "Developer Command Prompt for VS 2022" or ensure C++ workload is installed in VS Build Tools.
- **Tailscale can't connect:** Check that the machine isn't behind a restrictive corporate firewall. Tailscale usually works through NAT but some enterprise networks block it.
- **rpc-server crashes:** Check GPU memory with `nvidia-smi`. If another process is using all VRAM, kill it first.
