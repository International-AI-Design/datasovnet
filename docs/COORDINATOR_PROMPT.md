# Coordinator Activation — Prompt for Claude Code on Johnny's Mac

> **Open a new Claude Code session on your Mac and paste this to initiate the DataSovNet coordinator.**

---

## The Prompt

```
Read the DataSovNet docs at ~/Documents/01_VibeCoding/ferroai/workspaces/datasovnet/

I'm activating this Mac (M3 Max, 36GB) as the DataSovNet coordinator node. Two RPC worker nodes should already be online:

- Ernesto's 4090 (set up earlier today)
- Mark's gaming PC (just set up)

Here's what needs to happen:

1. Verify local setup:
   - Tailscale is connected (tailscale ip -4)
   - llama.cpp is built (~/.datasovnet/llama.cpp/build/bin/llama-server exists)
   - Model file exists (~/.datasovnet/models/ — should have DeepSeek-R1-Distill-Llama-70B)

2. Register both workers:
   - Run: bash ~/Documents/01_VibeCoding/ferroai/workspaces/datasovnet/scripts/coordinator.sh add-worker ernesto-4090 <ERNESTO_TAILSCALE_IP> 50052
   - Run: bash ~/Documents/01_VibeCoding/ferroai/workspaces/datasovnet/scripts/coordinator.sh add-worker marks-pc <MARKS_TAILSCALE_IP> 50052
   (I'll provide the IPs)

3. Health check: coordinator.sh health — verify both show RPC=UP

4. If the 70B model isn't downloaded yet, start with the 8B test model:
   - bash scripts/coordinator.sh download-model deepseek-r1-8b

5. Start distributed inference:
   - bash scripts/coordinator.sh start-inference
   - This launches llama-server with --rpc pointing to both workers

6. Test it:
   - bash scripts/coordinator.sh chat "What is data sovereignty and why does it matter for individuals?"

Report the Tailscale IPs, worker status, model loading status, and tokens/sec once running.
```

---

## Before Running This

Make sure you've already done:
- [x] `brew install cmake` (check: `cmake --version`)
- [x] `brew install --cask tailscale` (check: Tailscale running, signed in)
- [x] Ran `install.sh` as coordinator OR manually built llama.cpp
- [x] Started model download (`coordinator.sh download-model deepseek-r1-70b`)
- [x] Ernesto's PC is online with rpc-server running
- [x] Mark's PC is online with rpc-server running

## Quick Validation Before Full Model

If the 70B model is still downloading, test the pipeline with the 8B model first:
```
bash scripts/coordinator.sh download-model deepseek-r1-8b
bash scripts/coordinator.sh start-inference
bash scripts/coordinator.sh chat "Hello from the distributed network"
```

This validates Tailscale connectivity + RPC distribution + inference pipeline without waiting for the 42GB download.
