# Persistence

What survives reboot, what doesn't, and how user data is ranked.

## 0. The impermanence rule

| Survives reboot | Path | Why |
|-----------------|------|-----|
| Packages + system | `/nix` | Nix store, dedicated subvolume |
| User home | `/home/m` | Bind-mount from `/persistent/home/m` |
| System state | `/persistent` | Dedicated Btrfs subvolume |
| **Everything else** | `/`, `/tmp`, `/run` | **Wiped every boot** |

Before proposing any fix: ask "does this survive reboot without touching
Nix?" If no — it must go in the flake. The whitelist of bind-mounted
persistent paths lives in `nix/modules/core/impermanence.nix`.

## 1. What is protected, and how

The backup posture is deliberately narrow, by policy:

| Asset | Strategy | Where | Snapshot history |
|-------|----------|-------|------------------|
| System config | Git / GitHub | `github.com/mvrozanti/mandragora` | Full git history |
| sops **age master key** | Weekly VPS mirror + validity check | `nix/modules/core/backup.nix` → `age-key-backup` service, `/home/opc/backups/age-key/keys.txt` on the VPS | Latest copy only (single file, mirror-overwrite) |
| Everything else in Seafile libraries | Seafile **live sync** only | Seafile server ↔ desktop | **None — by policy** |

There is intentionally **no off-host snapshot history** for user data.
This is a conscious decision, not a gap to be closed. The accepted risk:

- A deletion or ransomware event **propagates** through Seafile's live
  sync to every replica; there is no prior-version vault to roll back to.
- `~/Pictures` is **not** in any Seafile library, so it has no off-host
  copy at all.

If that risk profile ever becomes unacceptable, the lever is a real
snapshot tier (Seafile server-side history, a versioned object store, or
a restic-style repo) — but until then the only automated off-host
artifact is the age key, because losing it locks every other secret out
forever while losing user files is merely painful.

## 2. The age-key disaster-recovery mirror

`nix/modules/core/backup.nix` defines the system service
`age-key-backup` and a weekly timer (`OnCalendar=Sat 06:00`,
`Persistent=true`, `RandomizedDelaySec=1h`). It is the *only* automated
off-host backup on the system.

- **What:** the sops age master key at `/persistent/secrets/keys.txt`
  (root-owned `0600`) — the one secret that decrypts every other secret
  in the tree.
- **Where:** `/home/opc/backups/age-key/keys.txt` on `mandragora-vps`,
  reached over the tailnet.
- **Runs as root** (must read the `0600` root-owned key), but the
  network hop is done as user `m`: the service shells out via
  `runuser -u m -- ssh …` because root has no VPS key and m does. The
  same BatchMode SSH pattern as `gource-renderer-prewarm`.
- **Key never touches argv, env, or logs.** The key value is streamed
  over stdin — `ssh … 'umask 077; mkdir -p …; cat > …/keys.txt'
  < /persistent/secrets/keys.txt`. It is never an argument, never an
  environment variable, never echoed. Only the file *path* is passed
  around.
- **Verification, same run:** after the upload the script (a) captures
  the local `sha256sum` into a shell variable (never printed), (b) reads
  the remote `sha256sum` back over ssh, (c) fails on mismatch, and
  (d) runs `age-keygen -y` on the local key for validity, discarding the
  output (which is only the *public* key) and using the exit code alone.
  Any failure exits nonzero.
- **Failure alerting:** `OnFailure=backup-failed@age-key-backup.service`
  fires `backup-alert`, which pings Telegram (`telegram-notify`, with a
  `notify-send` fallback) and best-effort records a marker under
  `/persistent/backup/last-failure`.

## 3. Restore runbook

To recover the age key onto a fresh (or wiped) desktop, copy the mirror
back and restore its root-only permissions:

```
scp opc@mandragora-vps:/home/opc/backups/age-key/keys.txt /tmp/keys.txt
sudo install -o root -g root -m 0600 /tmp/keys.txt /persistent/secrets/keys.txt
sudo shred -u /tmp/keys.txt
```

With `/persistent/secrets/keys.txt` back in place, sops-nix can decrypt
every secret in the tree on the next rebuild. Everything else user-data
is recovered by re-syncing the relevant Seafile libraries — there is no
snapshot history to restore (see §1).

The offline cold-storage copy of the age key (paper / USB in a safe, per
[`docs/secrets.md`](secrets.md) §5) remains the authoritative last-resort
source; the VPS mirror is the automated, always-fresh convenience copy.
