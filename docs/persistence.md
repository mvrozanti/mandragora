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

A four-tier ranking for user data by replaceability. None of the
mirroring/backup automation below has shipped yet — the actual state today
is "everything under `/persistent/home/m` survives reboot; nothing is
mirrored off-host." This table records the design target.

| Tier | Data | Strategy | Location |
|------|------|----------|----------|
| Invulnerable | Photos, irreplaceable archives | Local + remote mirror | Btrfs subvolume + Seafile + arch-slave + (eventually) Oracle VPS |
| Resilient | Documents | Real-time sync + history | Seafile on arch-slave |
| Bulk | Movies, media | Remote mount / on-demand | arch-slave (SSHFS / NFS) |
| Ephemeral | Public git, scratch | Version control only | Local / re-clonable |

`~/Documents`, `~/Projects`, `~/Photos`, `~/Media` are the intended mount
points for the four tiers respectively. Until the Seafile / arch-slave /
mirror plumbing is wired, they are plain directories under `/persistent/home/m`.
