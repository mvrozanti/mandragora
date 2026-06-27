# gpu-lock contract

Mandragora has one GPU (RTX 5070 Ti, 16 GB). All CUDA / PyTorch / Ollama workloads must serialize through `gpu-lock`. Semantics: **respect the holder, fail fast** — a running holder is never preempted; new arrivals get a busy result and decide what to do.

- **Any language:** `gpu-lock run --name <yourname> --expect <Ns> -- <cmd>` — exits 75 with `{"error":"gpu-busy","holder":{...}}` JSON to stderr if held.
- **Python in-tree:** `from gpu_lock import gpu_lock, GpuBusy; with gpu_lock.acquire("name", expected_seconds=N): ...` — raises `GpuBusy(holder=...)` if held.

**PyTorch holders MUST call `torch.cuda.empty_cache()` before exit.** Without it the CUDA allocator keeps the pages and the next holder sees a near-full GPU — this caused a real incident on 2026-04-27.

**Respect execution.** Do not signal/kill the holder PID. Do not loop tight on `acquire`. On `GpuBusy`, back off — retry later, fall back to CPU, or surface the busy state to the user.

**Ollama is currently outside the protocol** (crush, llm-via-telegram, MCP server hit `:11434` directly). Manually `sudo systemctl stop ollama` if you need guaranteed isolation.

Full contract:
- Claude: invoke the `gpu-lock` skill (much more detail than this rule).
- Other agents (Gemini, Qwen, local LLM): read `/etc/nixos/mandragora/docs/gpu.md`.
