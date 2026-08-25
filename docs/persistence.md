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
  in the tree — **encrypted to a dedicated lifeboat age recipient**
  before it leaves the desktop.
- **Where:** `/home/opc/backups/age-key/keys.txt.age` on
  `mandragora-vps`, reached over the tailnet. Alongside it sits
  `lifeboat.aes` — the lifeboat identity itself, AES-256 encrypted under
  a passphrase (see §3). Together those two files make the VPS a
  self-sufficient recovery point: nothing else is needed but the
  passphrase.
- **Why encrypted:** the ciphertext this key unlocks is published in a
  public GitHub repo, so a plaintext mirror made a VPS compromise
  equivalent to a total secret compromise. The lifeboat recipient's
  private half is held in cold storage (and, for convenience, in sops at
  `age_backup/lifeboat_key`), so the VPS holds a blob it cannot open.
  The service deletes any legacy plaintext `keys.txt` it finds.
- **Runs as root** (must read the `0600` root-owned key), but the
  network hop is done as user `m`: the service shells out via
  `runuser -u m -- ssh …` because root has no VPS key and m does. The
  same BatchMode SSH pattern as `gource-renderer-prewarm`.
- **Key never touches argv, env, or logs.** The ciphertext is streamed
  over stdin — `ssh … 'umask 077; mkdir -p …; cat > …/keys.txt.age'`.
  Neither the key nor the ciphertext is ever an argument, an environment
  variable, or echoed. Only file *paths* and the lifeboat *public* key
  are passed around.
- **Verification, same run:** before upload the script asserts the
  artifact begins with the `age-encryption.org` header and contains no
  `AGE-SECRET-KEY-` line, refusing to upload otherwise. After upload it
  (a) captures the local ciphertext `sha256sum` into a shell variable
  (never printed), (b) reads the remote `sha256sum` back over ssh,
  (c) fails on mismatch, and (d) runs `age-keygen -y` on the local key
  for validity, discarding the output (only the *public* key) and using
  the exit code alone. Any failure exits nonzero.
- **Failure alerting:** `OnFailure=backup-failed@age-key-backup.service`
  fires `backup-alert`, which pings Telegram (`telegram-notify`, with a
  `notify-send` fallback) and best-effort records a marker under
  `/persistent/backup/last-failure`.

## 3. Restore runbook

To recover the age key onto a fresh (or wiped) desktop, copy the mirror
back and restore its root-only permissions:

```
scp opc@mandragora-vps:/home/opc/backups/age-key/keys.txt.age /tmp/keys.age
age --decrypt -i /path/to/lifeboat-key.txt -o /tmp/keys.txt /tmp/keys.age
sudo install -o root -g root -m 0600 /tmp/keys.txt /persistent/secrets/keys.txt
sudo shred -u /tmp/keys.txt /tmp/keys.age
```

`lifeboat-key.txt` is the lifeboat identity. **Without it the VPS mirror
cannot be opened** — that is the point of the design. There are three
places to get it, in descending order of preference:

1. **Cold storage** (paper / USB in a safe). Authoritative.
2. **The VPS itself**, at `/home/opc/backups/age-key/lifeboat.aes`,
   AES-256-CBC under a passphrase. This is what makes the VPS a complete
   recovery point — VPS access plus the passphrase reconstructs
   everything, no physical media required. Decrypt it with `aescrypt -d`,
   or with plain openssl on any machine that lacks the tooling:

   ```
   openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -a \
     -in lifeboat.aes -out lifeboat-key.txt
   ```

3. **sops**, at `age_backup/lifeboat_key` — convenience only, since it
   needs the master key this whole runbook exists to recover.

The consequence worth internalising: that passphrase is now the single
point of failure in both directions. It is the only thing between a VPS
compromise and the entire secret store, and forgetting it makes the
off-site copy unopenable. Keep cold storage regardless.

With `/persistent/secrets/keys.txt` back in place, sops-nix can decrypt
every secret in the tree on the next rebuild. Everything else user-data
is recovered by re-syncing the relevant Seafile libraries — there is no
snapshot history to restore (see §1).

The offline cold-storage copy of the age key (paper / USB in a safe, per
[`docs/secrets.md`](secrets.md) §6) remains the authoritative last-resort
source; the VPS mirror is the automated, always-fresh convenience copy.
