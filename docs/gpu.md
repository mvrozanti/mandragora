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

`gpu-lock` is a Python wrapper around the `gpu_lock` library — a non-blocking `fcntl.flock` mutex on `/dev/shm/gpu-lock/gpu.lock` with a sidecar JSON file describing the current holder. The bots (`im-gen`, `llm-via-telegram`) coordinate on the same primitive directly via `import gpu_lock`; the CLI extends the same protocol to non-Python and shell callers.

Semantics are **respect-the-holder**, not cooperative preemption: a running holder is never signalled or interrupted. New arrivals fail fast — the caller decides whether to retry, fall back, or surface the busy state.

The library lives at `.local/share/gpu-lock/gpu_lock.py`, the CLI at `.local/share/gpu-lock/gpu_lock_cli.py`, both packaged via `pkgs/gpu-lock.nix` and exported from `modules/core/ai-local.nix` systemPackages.

### Subcommands

```
gpu-lock run --name <name> --expect <seconds> -- <cmd> [args...]
gpu-lock status
```

- `run` tries to acquire the lock without blocking, spawns `cmd`, releases on exit. If the lock is held, exits `75` (`EX_TEMPFAIL`) and prints `{"error":"gpu-busy","holder":{...}}` JSON to stderr.
- `status` shows the current holder (pid, name, held_for, expected_remaining).

### Storage

- Lock dir: `/dev/shm/gpu-lock/` (RAM-backed; auto-clears on reboot).
- `gpu.lock` — the `fcntl` mutex file (always present once anyone has used the lock; flock state is kernel-side).
- `gpu.lock.holder` — JSON with `pid`, `name`, `since`, `expected_seconds` for the current holder.

### Coordination rules

1. **One holder at a time.** `acquire` is non-blocking. If free, you get the lock. If held, you get `GpuBusy(holder=...)` immediately.
2. **No preemption.** The holder is never signalled, never killed, never asked to yield. Whatever is running runs to completion. This is a deliberate trade against responsiveness — interactive callers (the Telegram bot) are expected to tell the user "GPU busy, try in ~Ns" rather than waiting indefinitely or pre-empting a long-running training job.
3. **PID death releases the lock.** `fcntl` flocks are released by the kernel on process exit, so a crashed holder doesn't wedge the system — the next acquirer just gets the lock. (The stale `gpu.lock.holder` JSON file may linger for a moment until overwritten, but the lock itself is free.)
4. **No `eta`, no priority, no queue ordering.** First non-busy `acquire` wins. `expected_seconds` is metadata for `status` and `GpuBusy.expected_remaining()`, not enforced.
5. **PyTorch holders MUST clean VRAM before release.** Call `torch.cuda.empty_cache()` before exiting the `with gpu_lock.acquire(...)` block, or the caching allocator keeps the pages and the next holder sees a near-full GPU. This bit us on 2026-04-27.

### Idiomatic use

Shell, with retry-after-busy left to the caller's policy:

```bash
if ! gpu-lock run --name trading --expect 3600 -- ./run-walk-forward.sh; then
    rc=$?
    if [ "$rc" = "75" ]; then
        echo "GPU busy, will not start training run"
        exit 75
    fi
    exit "$rc"
fi
```

Python (CLI wrapper, any project):

```python
import subprocess
proc = subprocess.run([
    "gpu-lock", "run",
    "--name", "trading", "--expect", "3600",
    "--", "python", "walk_forward.py",
])
if proc.returncode == 75:
    raise RuntimeError("GPU was busy; aborted")
```

Python (direct library use, in-tree projects):

```python
from gpu_lock import gpu_lock, GpuBusy
import torch

try:
    with gpu_lock.acquire("trading", expected_seconds=3600):
        for fold in folds:
            run_fold(fold)
        torch.cuda.empty_cache()
except GpuBusy as busy:
    name = busy.holder["name"] if busy.holder else "unknown"
    eta = busy.expected_remaining()
    raise RuntimeError(
        f"GPU held by {name}; expected ~{eta:.0f}s remaining" if eta else f"GPU held by {name}"
    )
```

`gpu-lock status` to inspect.

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
- It does not preempt, queue, or rate-limit. One tenant at a time, fail-fast on contention.
- It does not retry. The caller decides whether to back off, fall back to CPU, or surface the busy state to a human.

This is intentional. The system is one user, one GPU, and a small number of well-known workload classes — heavyweight orchestration would cost more than it saves.

---

## See also

- [`../AGENTS.md`](../AGENTS.md) rule 15 — Non-Negotiable: hold `gpu-lock` around any GPU job.
- `~/.ai-shared/rules/gpu-lock.md` — short cross-agent rule (always loaded), points here for the long form.
- `~/.claude/skills/gpu-lock/SKILL.md` and `~/.gemini/skills/gpu-lock/SKILL.md` — full contract loaded on demand when the agent recognizes a GPU-related task. Source: [`../agent-skills/gpu-lock/SKILL.md`](../agent-skills/gpu-lock/SKILL.md).
- [`../local-llm.md`](../local-llm.md) — peer doc; what the local LLM agent should know about its environment.
- [`../modules/core/ai-local.nix`](../modules/core/ai-local.nix) — Ollama service definition.
- [`../pkgs/gpu-lock.nix`](../pkgs/gpu-lock.nix) — the package; implementation lives at `.local/share/gpu-lock/`.
