# GPU.md — Whole-GPU Mutex Convention

The Mandragora system has a single RTX 5070 Ti (16 GB). GPU workloads on this machine are **whole-or-nothing**: each tenant assumes it owns the entire device. That premise is intentional — fractional sharing (CUDA MPS, MIG) buys concurrency we do not need with one user, and would just turn contention into OOM.

This file documents how multiple workloads coordinate that single GPU.

---

## Tenants

| Workload class | Examples | Lifecycle |
|---|---|---|
| `llm` | `ollama-cuda` (systemd service) | Long-lived background tenant. Always wants GPU when up. |
| `imagegen` | ComfyUI / Forge / similar | Bursty foreground; user launches per session. |
| `trading` | XGBoost-GPU walk-forwards, RL training in `~/Projects/orderbook-algotrading` | Bursty foreground; runs are 30 min–several hours. |
| `other` | Ad-hoc CUDA work, model conversions, profiling | Bursty foreground. |

---

## The tool: `gpu-lock`

`gpu-lock` is a Python wrapper around the `gpu_lock` library — an `fcntl.flock` mutex on `/dev/shm/gpu-lock/gpu.lock` plus `SIGUSR1`-based cooperative preemption. The bots (`im-gen`, `llm-via-telegram`) coordinate on the same primitive directly via `import gpu_lock`; the CLI extends the same protocol to non-Python and shell callers.

The library lives at `.local/share/gpu-lock/gpu_lock.py`, the CLI at `.local/share/gpu-lock/gpu_lock_cli.py`, both packaged via `pkgs/gpu-lock.nix` and exported from `modules/core/ai-local.nix` systemPackages.

### Subcommands

```
gpu-lock run --name <name> --expect <seconds> \
             [--on-yield {sigusr1|sigterm|kill}] \
             [--timeout <seconds>] \
             -- <cmd> [args...]

gpu-lock status
gpu-lock yield [pid] [--reason "<text>"]
```

- `run` blocks until the lock is free, spawns `cmd`, releases on exit. Default `--on-yield sigusr1` forwards a yield request from another waiter to the child as `SIGUSR1` (so a CUDA program with a checkpoint handler can save state). `sigterm` is the right choice for programs that don't trap `SIGUSR1`. `kill` is the nuclear option.
- `status` shows the current holder and any queued waiters.
- `yield` sends `SIGUSR1` to the holder. With no pid, signals whoever is currently holding.

### Storage

- Lock dir: `/dev/shm/gpu-lock/` (RAM-backed; auto-clears on reboot).
- `gpu.lock` — the `fcntl` mutex file (always present once anyone has used the lock; flock state is kernel-side).
- `gpu.lock.holder` — JSON with `pid`, `name`, `since`, `expected_seconds` for the current holder.
- `gpu.lock.waiters` — JSON list of waiting callers with `pid`, `name`, `reason`, `since`.

### Coordination rules

1. **One holder at a time.** `acquire` blocks until the previous holder releases. No "claim rejected" — you wait, politely.
2. **Politeness is automatic.** When you call `acquire`, the library sends `SIGUSR1` to the current holder so it can choose to wrap up. The CLI forwards that signal (or `SIGTERM`/`SIGKILL`, your call) to your wrapped child.
3. **Cooperative yield is the holder's contract.** A well-behaved Python caller polls `gpu_lock.yield_requested()` between iterations and raises `GpuYieldRequested` to abort. A CLI-wrapped command receives the configured signal and must handle it. Programs that ignore the signal hold the lock until they're done.
4. **PID death releases the lock.** `fcntl` flocks are released by the kernel on process exit, so a crashed holder doesn't wedge the system — the next acquirer just gets the lock.
5. **No `eta`, no priority, no queue ordering.** First waiter to call `acquire` after release wins. `expected_seconds` is metadata for `status`, not enforced.
6. **PyTorch holders MUST clean VRAM before release.** Call `torch.cuda.empty_cache()` before exiting the `with gpu_lock.acquire(...)` block, or the caching allocator keeps the pages and the next holder sees a near-full GPU. This bit us on 2026-04-27.

### Idiomatic use

Shell:

```bash
gpu-lock run --name trading --expect 3600 --on-yield sigterm -- ./run-walk-forward.sh
```

Python (CLI wrapper, any project):

```python
import subprocess
subprocess.check_call([
    "gpu-lock", "run",
    "--name", "trading", "--expect", "3600",
    "--on-yield", "sigusr1",
    "--", "python", "walk_forward.py",
])
```

Python (direct library use, in-tree projects):

```python
from gpu_lock import gpu_lock, GpuYieldRequested
import torch

with gpu_lock.acquire("trading", expected_seconds=3600):
    try:
        for fold in folds:
            if gpu_lock.yield_requested():
                raise GpuYieldRequested("preempted; checkpointing")
            run_fold(fold)
    finally:
        torch.cuda.empty_cache()
```

`gpu-lock status` to inspect, `gpu-lock yield <pid>` to politely interrupt a holder when you need the GPU urgently.

---

## Ollama is the awkward case

Ollama runs as a systemd service (`services.ollama` in `modules/core/ai-local.nix`), always wanting GPU. It is **not** in the lease system today. The protocol is:

> **Before launching an `imagegen` or `trading` job that needs the GPU, manually `sudo systemctl stop ollama`. Restart it (`sudo systemctl start ollama`) when done.**

This is friction-tolerable because (a) trading runs are pre-planned, not ad-hoc, and (b) the user is the only client of all three workloads, so coordination is single-headed. If forgetting becomes a real problem, upgrade to a `gpu-arbiter.service` wrapper that holds the lock on Ollama's behalf and stops/restarts it when other workloads claim. The arbiter is **deferred until forgetting causes a real incident** — adding it now is speculative complexity.

---

## What `gpu-lock` does NOT do

- It does not prevent you from launching a CUDA process. Nothing intercepts at the kernel level. `gpu-lock` is a *convention*, not enforcement.
- It does not stop or start Ollama for you. See the section above.
- It does not detect VRAM exhaustion. If your workload OOMs, that is on you.
- It does not rate-limit, queue, or prioritize. One tenant at a time, first claim wins.

This is intentional. The system is one user, one GPU, and a small number of well-known workload classes — heavyweight orchestration would cost more than it saves.

---

## See also

- [`AGENTS.md`](AGENTS.md) rule 15 — Non-Negotiable: claim `gpu-lock` before launching any GPU job.
- [`local-llm.md`](local-llm.md) — peer doc; what the local LLM agent should know about its environment.
- [`modules/core/ai-local.nix`](modules/core/ai-local.nix) — Ollama service definition.
- [`.local/bin/gpu-lock.sh`](.local/bin/gpu-lock.sh) — the implementation.
