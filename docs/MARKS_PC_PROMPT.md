# Mark's PC Setup — Prompt for Claude Code

> **Copy-paste this into Claude Code on Mark's machine to kick off setup.**

---

## The Prompt

```
Clone the repo at https://github.com/International-AI-Design/datasovnet and read BOOTSTRAP.md.

This Windows gaming PC needs to be set up as an RPC worker node in the DataSovNet distributed AI inference network. Follow BOOTSTRAP.md step by step.

Key details:
- Role: RPC worker (NOT coordinator)
- Coordinator's Tailscale IP: I'll give you this once we know it
- RPC port: 50052
- Johnny's Mac will SSH into this machine as coordinator

Here's what needs to happen in order:

1. Detect GPU — run nvidia-smi and report what GPU and how much VRAM
2. Install Tailscale — use winget, then I'll sign in manually
3. Install build deps — Git, CMake, Visual Studio Build Tools with C++ workload, CUDA toolkit
4. Clone and build llama.cpp with -DGGML_RPC=ON -DGGML_CUDA=ON
5. Open Windows Firewall port 50052 for RPC
6. Start rpc-server on 0.0.0.0:50052
7. Report back: Tailscale IP, GPU specs, RPC server status

Also set up SSH server so the coordinator (Johnny's Mac) can manage this machine remotely:
- Enable OpenSSH Server via Windows features
- Start the sshd service
- Note the local IP and Tailscale IP

Go step by step, pausing after each major step so I can handle any manual parts (like signing into Tailscale or approving installs).
```

---

## What to Expect

Claude Code will:
1. Clone the repo into a working directory
2. Run through system detection (nvidia-smi)
3. Start installing prerequisites one by one
4. Build llama.cpp (~5-10 min compile on a gaming PC)
5. Configure and start the RPC worker
6. Set up SSH for remote management

**Manual steps you'll need to do:**
- Sign into Tailscale when the app opens (use your account)
- Approve any Windows UAC prompts
- If VS Build Tools installer opens a GUI, add "Desktop Development with C++"
- If CUDA needs downloading, approve the NVIDIA installer

**After it's done, you'll have:**
- `rpc-server.exe` running on port 50052
- Tailscale connected with a 100.x.y.z IP
- SSH server running for remote management
- All info needed for the coordinator to connect
