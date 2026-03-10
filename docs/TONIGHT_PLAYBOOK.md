# DataSovNet Deployment Playbook — Tonight at Mark's House

**Date:** 2026-03-10
**Goal:** Connect 3 machines into a distributed compute organism running DeepSeek-R1 70B across all GPUs

## The Network

| Node | Hardware | GPU Memory | Role |
|------|----------|-----------|------|
| Johnny's Mac | M3 Max | 36GB unified | **Coordinator** — loads model, runs llama-server |
| Ernesto's PC | RTX 4090 | 24GB VRAM | **RPC Worker** — contributes GPU compute |
| Mark's PC | Gaming PC | ~24GB VRAM (confirm!) | **RPC Worker** — contributes GPU compute |

**Total: ~84GB** — enough for DeepSeek-R1-Distill-Llama-70B at Q4_K_M (~42GB) with 30GB+ headroom for context

---

## Before You Leave the House

### On Johnny's Mac (do this now, it takes time)

**1. Make sure Tailscale is installed**
```bash
# Check if installed
tailscale version

# If not installed:
brew install --cask tailscale
# Then open Tailscale from Applications, sign in
```

**2. Run the DataSovNet installer on your Mac as COORDINATOR**
```bash
cd ~/Documents/01_VibeCoding/ferroai/workspaces/datasovnet
chmod +x install.sh
./install.sh
# When asked for role, pick: 2 (Coordinator)
```

**3. Start downloading the model (42GB — do this BEFORE leaving)**
```bash
~/.datasovnet/scripts/coordinator.sh download-model deepseek-r1-70b
# OR if coordinator.sh isn't linked yet:
bash ~/Documents/01_VibeCoding/ferroai/workspaces/datasovnet/scripts/coordinator.sh download-model deepseek-r1-70b
```

This downloads to `~/.datasovnet/models/`. ~42GB so start early.

**4. Also download a small test model (for quick validation)**
```bash
bash scripts/coordinator.sh download-model deepseek-r1-8b
```

**5. Get your Tailscale IP**
```bash
tailscale ip -4
# Note this down — workers need it
```

---

## At Mark's House

### Step 1: Install Tailscale on All Machines (5 min each)

**Mark's Windows PC:**
1. Download from https://tailscale.com/download/windows
2. Install and sign in (same Tailscale account or accept invite)
3. Open PowerShell: `tailscale ip -4` — note the IP

**Ernesto's PC (if Linux):**
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
tailscale ip -4  # note the IP
```

**Verify mesh connectivity:**
```bash
# From Johnny's Mac, ping both workers:
ping <marks-tailscale-ip>
ping <ernestos-tailscale-ip>
```

All machines should be reachable. If not, check Tailscale status on each machine.

### Step 2: Set Up Mark's PC as RPC Worker (15-20 min)

**Option A: PowerShell installer (recommended for Windows)**

Copy `install-windows.ps1` to Mark's PC via:
- USB drive
- Or from Johnny's Mac: `scp install-windows.ps1 mark@<marks-ip>:~/`
- Or just open the file from the repo

```powershell
# On Mark's PC, open PowerShell as Administrator:
Set-ExecutionPolicy Bypass -Scope Process
.\install-windows.ps1
```

This will:
- Detect his GPU (type + VRAM — **note the specs!**)
- Install Git, CMake, VS Build Tools if missing
- Build llama.cpp with CUDA + RPC
- Configure as worker node

**Option B: Manual setup (if installer has issues)**

```powershell
# Install prerequisites with winget
winget install Git.Git
winget install Kitware.CMake
winget install Microsoft.VisualStudio.2022.BuildTools
# Then add "Desktop Development with C++" workload in VS Installer

# Clone and build llama.cpp
git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp
cmake -B build -DGGML_CUDA=ON -DGGML_RPC=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release

# Start RPC worker
.\build\bin\Release\rpc-server.exe --host 0.0.0.0 --port 50052
```

**Start the RPC worker:**
```
%USERPROFILE%\.datasovnet\start-worker.bat
```
Leave this running!

### Step 3: Set Up Ernesto's PC as RPC Worker (10-15 min)

```bash
# Copy install script or run directly:
curl -fsSL https://raw.githubusercontent.com/International-AI-Design/datasovnet/main/install.sh | bash
# OR from local:
bash /path/to/install.sh

# When prompted:
# Role: 1 (Worker)
# Coordinator IP: <johnny's tailscale ip>

# Start the worker:
~/.datasovnet/start-worker.sh
```

### Step 4: Register Workers on Johnny's Mac (2 min)

```bash
# From Johnny's Mac:
cd ~/Documents/01_VibeCoding/ferroai/workspaces/datasovnet

bash scripts/coordinator.sh add-worker marks-pc <marks-tailscale-ip> 50052
bash scripts/coordinator.sh add-worker ernesto-4090 <ernestos-tailscale-ip> 50052

# Verify both are reachable:
bash scripts/coordinator.sh health
```

You should see both workers with `RPC=UP`.

### Step 5: Start Distributed Inference (5 min)

```bash
# Make sure the model finished downloading!
ls -lh ~/.datasovnet/models/

# Start the distributed server:
bash scripts/coordinator.sh start-inference

# It will:
# 1. Find the model file
# 2. Connect to both RPC workers
# 3. Distribute model layers across all 3 GPUs
# 4. Start llama-server on port 8080
```

Watch the log if it takes long:
```bash
tail -f ~/.datasovnet/inference.log
```

You should see lines like:
```
llm_load_tensors: offloading 80 layers to GPU
llm_load_tensors: RPC[0] (marks-pc): 27 layers
llm_load_tensors: RPC[1] (ernesto-4090): 27 layers
llm_load_tensors: Metal: 26 layers
```

### Step 6: Test It! (the fun part)

```bash
# Quick test:
bash scripts/coordinator.sh chat "What is data sovereignty and why does it matter?"

# Interactive chat:
bash scripts/coordinator.sh chat
# Then just type messages

# Or open in browser:
open http://localhost:8080
```

You're now running a 70B parameter reasoning model distributed across 3 computers. This IS the DataSov proof-of-concept.

---

## Troubleshooting

### "RPC worker not responding"
- Make sure `rpc-server` is running on the worker machine
- Check Tailscale: `ping <worker-ip>`
- Check the port: `nc -z <worker-ip> 50052`
- Firewall: Windows may block port 50052 — add firewall rule

### "Model loading takes forever"
- First load is slow (reading 42GB from disk)
- Subsequent loads are faster (OS file cache)
- Check memory: if a worker has less VRAM than expected, more layers stay on the coordinator

### "Out of memory"
- Reduce context: add `--ctx-size 4096` to start-inference
- Use a smaller model: `coordinator.sh download-model deepseek-r1-8b`
- Check actual VRAM: `nvidia-smi` on worker machines

### "Windows build fails"
- Make sure CUDA toolkit is installed (not just the driver)
- Use "Developer Command Prompt for VS 2022" or "x64 Native Tools"
- If cmake fails: `cmake -B build -DGGML_CUDA=ON -DGGML_RPC=ON -G "Visual Studio 17 2022"`

### "Can't reach other machines"
- All machines must be on the same Tailscale network (same account or invited)
- Run `tailscale status` on each machine — all should show "active"
- If behind corporate firewall: Tailscale uses DERP relays as fallback

---

## Quick Test Without the Big Model

If the 42GB model isn't downloaded yet, test the pipeline with the 8B model:

```bash
bash scripts/coordinator.sh download-model deepseek-r1-8b   # ~5GB, fast
bash scripts/coordinator.sh start-inference
bash scripts/coordinator.sh chat "Explain distributed computing in one paragraph"
```

This validates the entire pipeline (Tailscale -> RPC -> distributed inference -> response) without waiting for the big download.

---

## What Success Looks Like

When everything is working:
1. `coordinator.sh health` shows all workers `RPC=UP`
2. `coordinator.sh start-inference` loads model across all GPUs
3. `coordinator.sh chat` gets intelligent responses from a 70B reasoning model
4. The inference log shows layers distributed across all 3 machines

**This is the DataSov proof-of-concept: three separate machines acting as one compute organism.**

---

## After Tonight

- [ ] Mark's GPU specs confirmed and documented
- [ ] All 3 machines on Tailscale mesh
- [ ] Distributed inference validated with 70B model
- [ ] Performance benchmarked (tokens/sec)
- [ ] Next: Mission Control dashboard to visualize this
- [ ] Next: Set up workers as systemd/startup services (auto-start on boot)
