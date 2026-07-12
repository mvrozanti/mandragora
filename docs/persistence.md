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

## 1. User-data ranking (intent)

A four-tier ranking for user data by replaceability. The Resilient
(Documents) tier now ships an off-host restic backup; the other tiers
remain design targets. The rest of the intent below records where each
tier is headed.

| Tier | Data | Strategy | Location | Status |
|------|------|----------|----------|--------|
| Invulnerable | Photos, irreplaceable archives | Local + remote mirror | Btrfs subvolume + Seafile + arch-slave + (eventually) Oracle VPS | Pending — `~/Pictures` is 29G; the VPS restic target has only 27G free of 199G, so photos are excluded by design until the arch-slave / Seafile target lands |
| Resilient | Documents | Off-host restic + retention | `nix/modules/core/backup.nix` → `sftp:opc@mandragora-vps` | **Shipped** — daily `restic-backup` of `/persistent/home/m/Documents` (7G, includes the obsidian vault); weekly `restic-lifeboat` integrity check |
| Bulk | Movies, media | Remote mount / on-demand | arch-slave (SSHFS / NFS) | Pending |
| Ephemeral | Public git, scratch | Version control only | Local / re-clonable | N/A — re-clonable |

`~/Documents`, `~/Projects`, `~/Photos`, `~/Media` are the intended mount
points for the four tiers respectively. Until the Seafile / arch-slave /
mirror plumbing is wired, they are plain directories under `/persistent/home/m`.

## 2. Resilient tier: the restic backup

`nix/modules/core/backup.nix` runs a system service `restic-backup` as
user `m` (SSHes to `opc@mandragora-vps` with m's keys — root has no VPS
key, so this cannot be a root or systemd `--user` service). Daily timer,
`Persistent=true`, `RandomizedDelaySec=45m`.

- **Repository:** `sftp:opc@mandragora-vps:/home/opc/backups/restic`,
  reached over the tailnet via the same BatchMode SSH pattern as
  `gource-renderer-prewarm`.
- **Backup set:** `/persistent/home/m/Documents` only (7G, dedup+zstd
  fits the 27G-free VPS budget; the 14M obsidian vault lives inside it).
- **Excluded:** `~/Pictures` (29G — does not fit; pending the
  arch-slave / Seafile target), plus caches / `node_modules` / `.git` of
  throwaway clones via `nix/snippets/restic-excludes.txt`, and `--exclude-caches`.
- **Not backed up — `~/.ssh`:** the restic repo lives on the very host
  those keys unlock. Backing the key into the repo it protects is
  circular and buys nothing; the keys are re-provisioned declaratively.
- **Retention:** `--keep-daily 7 --keep-weekly 4 --keep-monthly 6`,
  with `prune` once a week (Sundays).
- **Upload cap:** `--limit-upload 8192` KiB/s so a big first snapshot
  can't saturate the link.
- **First run:** the service runs `restic snapshots || restic init`, so
  an uninitialized repo self-initializes idempotently.

### Password handling

The repo password is auto-generated on first run into
`/persistent/backup/restic.pass` (`m:users 0600`) via
`openssl rand -base64 32` behind a `[ -s ]` guard. It is passed with
`RESTIC_PASSWORD_FILE` and **never appears in the nix store, the repo,
or logs**. It is deliberately *not* derived from the sops age key, and
**not** backed up into the restic repo (that would be circular). Mirror
`/persistent/backup/restic.pass` by hand to the cold-storage lifeboat
alongside the age key — without it the off-host snapshots are
undecryptable after a total desktop loss.

## 3. Lifeboat verification

`restic-lifeboat` (weekly, Saturdays) asserts the recovery chain is
still intact and alerts on any failure (reuses `telegram-notify`, with
`notify-send` fallback; `OnFailure` also writes a persistent marker to
`/persistent/backup/last-failure`):

1. the sops age key at `/persistent/secrets/keys.txt` exists and is a
   valid age identity — checked with `age-keygen -y` (which prints only
   the *public* key; the private half is never logged),
2. the restic repo is reachable and passes
   `restic check --read-data-subset=2%` (integrity spot-check).

## 4. Restore runbook

```
export RESTIC_REPOSITORY=sftp:opc@mandragora-vps:/home/opc/backups/restic
export RESTIC_PASSWORD_FILE=/persistent/backup/restic.pass   # or the cold-storage copy

restic snapshots                                  # list restore points
restic restore latest --target /tmp/restore       # newest snapshot
restic restore <id> --target /tmp/restore --include /persistent/home/m/Documents/foo
```

### Circularity caveat (recovering from total desktop loss)

The restic repo lives on the VPS, reachable via an SSH key that is
inside the desktop that just died — and the key is intentionally *not*
in the backup. So recovery from a total loss is **not** self-contained;
the chain is:

1. Re-provision a machine from the flake (declarative), which restores
   m's SSH keys and tailscale, OR reach the VPS out-of-band via the
   Oracle web console / a fresh SSH key added there.
2. Provide the **restic password** — either `/persistent/backup/restic.pass`
   restored from the cold-storage lifeboat, or regenerated is useless
   (a new random password cannot open the old repo), so the manual
   mirror above is load-bearing.
3. The sops **age master key** (cold storage, per `docs/secrets.md` §5)
   is what unlocks every other secret in the tree; it is included in the
   backup set only as convenience, never as the sole copy — its
   authoritative home is the offline lifeboat.

In short: the desktop can be rebuilt from Nix + the two cold-storage
artefacts (age key, restic password). Losing both cold-storage copies
*and* the desktop means the off-host snapshots are unrecoverable — which
is why the lifeboat check runs weekly.

> Note: no real backup has been executed from this branch — the VPS
> restic slot is provisioned at deploy time, not by this change.
