---
name: gpu-lock
description: Use when about to launch any GPU/CUDA/PyTorch/Ollama workload, when wrapping a program that uses an LLM or image generator, when handling GPU coordination on Mandragora, or when working with the bots (im-gen, llm-via-telegram, crush, MCP server). Loads the full Mandragora gpu-lock contract — cooperative-yield protocol, CLI verbs, library API, VRAM cleanup discipline, signal semantics, hard rules.
---

# gpu-lock — GPU coordination on Mandragora

This machine has one GPU (RTX 5070 Ti, 16 GB). Workloads assume exclusive access. The `gpu-lock` primitive enforces cooperative serialization with cooperative preemption, not first-claimant-wins.

## When this applies

Anything that touches CUDA: PyTorch, TensorFlow, diffusers, Ollama clients (crush, llm-via-telegram, MCP server), nvidia-smi-monitored work, model loading, inference, fine-tuning, training, profiling.

## Two ways in

**CLI (any language):**

```
gpu-lock run --name <yourname> --expect <seconds> [--on-yield {sigusr1|sigterm|kill}] -- <cmd>
```

Acquires the `fcntl` mutex on `/dev/shm/gpu-lock/gpu.lock`, runs cmd, releases on exit. If another caller arrives while you hold the lock, your child receives the chosen signal so it can checkpoint or exit cleanly. Default `sigusr1` is for programs that trap it; `sigterm` for everything else; `kill` is the nuclear option.

**Python library (in-tree projects):**

```python
from gpu_lock import gpu_lock, GpuYieldRequested
import torch

with gpu_lock.acquire("yourname", expected_seconds=N):
    try:
        for step in work:
            if gpu_lock.yield_requested():
                raise GpuYieldRequested("preempted")
            do_step(step)
    finally:
        torch.cuda.empty_cache()
```

`PYTHONPATH` must include `/etc/nixos/mandragora/.local/share/gpu-lock` for the import to resolve. Mandragora-managed services already set this; ad-hoc scripts can either set it themselves or just use the CLI wrapper.

## Hard rules

1. **PyTorch users MUST `torch.cuda.empty_cache()` before exit.** Without it, the caching allocator keeps the pages and the next holder sees a near-full GPU. This caused a real incident on 2026-04-27 — a Flux render left 13.7 GiB of cached pages, forcing every subsequent Ollama call into CPU offload mode (2+ minute response times until im-gen restarted).
2. **Cooperative yield is the holder's contract.** Poll `gpu_lock.yield_requested()` between iterations and raise `GpuYieldRequested` to abort, or trap your `--on-yield` signal in CLI-wrapped programs. Programs that ignore the request hold the lock until they're done — fine for short jobs, antisocial for long ones.
3. **No `sys.path.insert("/home/m/Projects/gpu-lock")`** — that path is a bridge symlink for legacy callers and will go away in Phase 2 of the migration. Use `PYTHONPATH` or the CLI wrapper.
4. **Ollama is currently outside the protocol.** Crush, llm-via-telegram, and the local MCP server all hit `http://127.0.0.1:11434` directly without going through the lock. Until the Ollama-fronting proxy ships (Layer 2), expect interleaving — manually `sudo systemctl stop ollama` before exclusive workloads if you need guaranteed isolation.

## Inspection and forced yield

- `gpu-lock status` — current holder + waiters
- `gpu-lock yield <pid>` — politely request a yield; sends `SIGUSR1` to the holder
- `gpu-lock yield` (no pid) — yields whoever is currently holding
- State files in `/dev/shm/gpu-lock/` (RAM-backed, auto-clears on reboot): `gpu.lock` (the fcntl mutex), `gpu.lock.holder` (JSON), `gpu.lock.waiters` (JSON)

## Long form

Full design rationale, storage layout, idiomatic patterns, what the tool deliberately does NOT do: `/etc/nixos/mandragora/docs/gpu.md`.
