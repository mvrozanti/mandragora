---
name: gpu-lock
description: Use when about to launch any GPU/CUDA/PyTorch/Ollama workload, when wrapping a program that uses an LLM or image generator, when handling GPU coordination on Mandragora, or when working with the bots (im-gen, llm-via-telegram, crush, MCP server). Loads the full Mandragora gpu-lock contract — non-blocking respect-the-holder protocol, CLI verbs, library API, VRAM cleanup discipline, hard rules.
---

# gpu-lock — GPU coordination on Mandragora

This machine has one GPU (RTX 5070 Ti, 16 GB). Workloads assume exclusive access. The `gpu-lock` primitive enforces cooperative serialization with **respect-the-holder** semantics: a running holder is never interrupted; new arrivals fail fast and the caller decides what to do (retry, fall back, surface the busy state to the user).

## When this applies

Anything that touches CUDA: PyTorch, TensorFlow, diffusers, Ollama clients (crush, llm-via-telegram, MCP server), nvidia-smi-monitored work, model loading, inference, fine-tuning, training, profiling.

## Two ways in

**CLI (any language):**

```
gpu-lock run --name <yourname> --expect <seconds> -- <cmd>
```

Tries the `fcntl` mutex on `/dev/shm/gpu-lock/gpu.lock` non-blocking. If free: runs cmd, releases on exit. If held: exits 75 (`EX_TEMPFAIL`) and prints `{"error":"gpu-busy","holder":{...}}` JSON to stderr. The running holder is never signalled.

**Python library (in-tree projects):**

```python
from gpu_lock import gpu_lock, GpuBusy
import torch

try:
    with gpu_lock.acquire("yourname", expected_seconds=N):
        for step in work:
            do_step(step)
        torch.cuda.empty_cache()
except GpuBusy as busy:
    print(f"GPU held by {busy.holder['name']}, ~{busy.expected_remaining():.0f}s remaining")
```

`PYTHONPATH` must include `/etc/nixos/mandragora/.local/share/gpu-lock` for the import to resolve. Mandragora-managed services already set this; ad-hoc scripts can either set it themselves or just use the CLI wrapper.

## Hard rules

1. **PyTorch users MUST `torch.cuda.empty_cache()` before exit.** Without it, the caching allocator keeps the pages and the next holder sees a near-full GPU. Real incident on 2026-04-27: a Flux render left 13.7 GiB of cached pages, forcing every subsequent Ollama call into CPU offload mode (2+ minute response times until im-gen restarted).
2. **Respect execution.** A running holder is not preempted, signalled, or killed. If `acquire` raises `GpuBusy`, your job is to back off — retry later, fall back to CPU, or tell the user. Do not `os.kill` the holder PID and do not loop tight on `acquire`.
3. **No `sys.path.insert("/home/m/Projects/gpu-lock")`** — that path is a bridge symlink for legacy callers and will go away in Phase 2 of the migration. Use `PYTHONPATH` or the CLI wrapper.
4. **Ollama is currently outside the protocol.** Crush, llm-via-telegram, and the local MCP server all hit `http://127.0.0.1:11434` directly without going through the lock. Until the Ollama-fronting proxy ships (Layer 2), expect interleaving — manually `sudo systemctl stop ollama` before exclusive workloads if you need guaranteed isolation.

## Inspection

- `gpu-lock status` — current holder (pid, name, held_for, expected_remaining)
- State files in `/dev/shm/gpu-lock/` (RAM-backed, auto-clears on reboot): `gpu.lock` (the fcntl mutex), `gpu.lock.holder` (JSON)

## Long form

Full design rationale, storage layout, idiomatic patterns, what the tool deliberately does NOT do: `/etc/nixos/mandragora/docs/gpu.md`.
