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

`gpu-lock` is a lightweight `flock`-based lease, modelled on `mandragora-lock`'s pattern. It is **not** a scheduler — there is no queue, no preemption, no fairness logic. It is a mutex with metadata so a workload can see who is holding the GPU and decide whether to wait.

The script lives at `.local/bin/gpu-lock.sh` and is exposed system-wide via `modules/user/home.nix` (per AGENTS.md rule 2 "Language Purity": shell code lives in `.local/bin/`, not embedded in Nix).

### Subcommands

```
gpu-lock claim   --workload {llm|imagegen|trading|other} \
                 --scope   "<short description>" \
                 [--eta    <duration>]      # e.g. 30min, 2h — soft hint, not enforced
                 [--owner-pid <pid>]        # enables liveness-aware auto-prune

gpu-lock release <session>
gpu-lock list
gpu-lock prune
```

`claim` prints the session id on stdout; capture it for `release`.

### Storage

- Lock dir: `/dev/shm/gpu-lock/` (RAM-backed; auto-clears on reboot).
- Per-claim file: `<UTC-ISO>-<rand>.lock` containing `session`, `workload`, `scope`, `agent`, `started`, optional `eta`, optional `owner_pid`.
- Single `/dev/shm/gpu-lock/.claim.lock` flock-held during check-and-write to make `claim` race-free (same pattern as `mandragora-lock`).

### Coordination rules

1. **One lock at a time.** `claim` rejects if any other lock is present and live.
2. **Live PID is sacred.** A foreign lock with a live `owner_pid` is never auto-released. Wait or ask the holder.
3. **Dead PIDs auto-prune.** A lock with `owner_pid` that no longer exists AND a file mtime older than 30s is pruned automatically during the next `claim`/`prune` call.
4. **No `owner_pid` → TTL-only, never auto-pruned.** Use this for shells or scripts where you cannot pass `$$` (rare). Be deliberate; these locks survive until manually released.
5. **`eta` is a hint, not a deadline.** It tells the next caller roughly how long to wait. Nothing enforces it.
6. **Release before exit.** Wrap your run in a trap. Forgetting is the most common failure mode.

### Idiomatic use

In a shell script that wants the GPU:

```bash
session=$(gpu-lock claim --workload trading --scope "T30 walk-forward 87d" --eta 1h --owner-pid $$) || {
  echo "GPU busy:" >&2
  gpu-lock list >&2
  exit 1
}
trap 'gpu-lock release "$session"' EXIT
# ... run the GPU job ...
```

In a Python script:

```python
import os, subprocess, atexit
session = subprocess.check_output([
    "gpu-lock", "claim",
    "--workload", "trading",
    "--scope", "T30 walk-forward 87d",
    "--eta", "1h",
    "--owner-pid", str(os.getpid()),
], text=True).strip()
atexit.register(lambda: subprocess.run(["gpu-lock", "release", session]))
```

`gpu-lock list` to inspect, `gpu-lock prune` to clean up dead-PID locks manually.

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
