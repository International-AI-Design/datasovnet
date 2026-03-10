# Worker PC Setup — Prompt for Claude Code

> **Copy-paste this into Claude Code on any Windows worker machine (Mark's PC, Ernesto's PC, etc.) to kick off setup.**

---

## The Prompt

```
Clone the repo at https://github.com/International-AI-Design/datasovnet and read BOOTSTRAP.md.

This Windows PC needs to be set up as an RPC worker node in the DataSovNet distributed AI inference network. Follow BOOTSTRAP.md step by step — this is a WINDOWS machine.

Key details:
- Role: RPC worker (NOT coordinator)
- Coordinator: Johnny's M3 Max Mac (I'll provide the Tailscale IP later)
- RPC port: 50052

Here's what needs to happen in order:

1. Detect GPU — run nvidia-smi in PowerShell and report what GPU and how much VRAM
2. Install Tailscale — use winget, then I'll sign in manually
3. Install build deps:
   - Git: winget install Git.Git
   - CMake: winget install Kitware.CMake
   - Visual Studio Build Tools: winget install Microsoft.VisualStudio.2022.BuildTools
     (then add "Desktop Development with C++" workload)
   - CUDA toolkit if not already installed (check nvcc --version)
4. Clone llama.cpp to %USERPROFILE%\.datasovnet\llama.cpp
5. Build with: cmake -B build -DGGML_RPC=ON -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release
   Then: cmake --build build --config Release
6. Open Windows Firewall port 50052:
   New-NetFirewallRule -DisplayName "DataSovNet RPC" -Direction Inbound -Protocol TCP -LocalPort 50052 -Action Allow
7. Start rpc-server: .\build\bin\Release\rpc-server.exe --host 0.0.0.0 --port 50052
8. Enable OpenSSH Server so the coordinator can manage this machine remotely:
   - Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
   - Start-Service sshd
   - Set-Service -Name sshd -StartupType Automatic
   - New-NetFirewallRule -DisplayName "OpenSSH" -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow
9. Report back: Tailscale IP (tailscale ip -4), GPU name + VRAM, RPC server status, SSH status

Use PowerShell for everything. Run as Administrator when needed.
Go step by step, pausing after each major step so I can handle any manual parts (like signing into Tailscale or approving installs).
```

---

## What to Expect

Claude Code will:
1. Clone the repo into a working directory
2. Run nvidia-smi to detect the GPU
3. Install prerequisites via winget one by one
4. Build llama.cpp with CUDA + RPC (~5-10 min compile)
5. Open firewall ports (50052 for RPC, 22 for SSH)
6. Start the RPC worker
7. Enable OpenSSH server for remote management

**Manual steps you'll need to do:**
- Sign into Tailscale when the app opens (use Johnny's account)
- Approve any Windows UAC prompts
- If VS Build Tools installer opens a GUI, add "Desktop Development with C++"
- If CUDA toolkit isn't installed, download from nvidia.com/cuda-downloads

**After it's done, you'll have:**
- `rpc-server.exe` running on port 50052
- Tailscale connected with a 100.x.y.z IP
- SSH server running for remote management from Johnny's Mac
- All info needed for the coordinator to connect

## For Ernesto's PC (same prompt)

Ernesto's PC is also Windows with an RTX 4090. Use the exact same prompt above. The only difference is it may already have CUDA toolkit and possibly Ollama installed — Claude Code will detect and skip what's already there.
