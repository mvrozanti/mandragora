# mandragora-nixos — Deployment Guide

**Date:** 2026-04-25

## Overview

There is no remote deployment target. The "deployment" of this project is
either:

1. **In-place rebuild** on the running machine (the day-to-day case).
2. **Fresh install** from a NixOS live USB onto blank or replacement
   hardware (rare; documented here as the runbook).

For the day-to-day in-place rebuild, see
[development-guide.md](./development-guide.md). This document focuses on the
fresh install path.

## In-Place Rebuild (Day-to-Day)

```bash
sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora-desktop
```

The `mandragora-switch` zsh alias wraps this with git sync (rebuild + commit
+ push).

For risky changes, use `test` first (activates without changing the boot
default — a reboot rolls back):

```bash
sudo nixos-rebuild test --flake /etc/nixos/mandragora#mandragora-desktop
```

Roll back to the previous generation via the systemd-boot menu (boot menu
shows up to 10 generations) or:

```bash
sudo nixos-rebuild switch --rollback
```

## Fresh Install

The runbook lives in [`../install/INSTALL.md`](../install/INSTALL.md). This
section is the AI-facing summary.

### Prerequisites

- NixOS live USB booted on the target hardware.
- Ethernet (recommended) or working WiFi.
- The repo cloned or copied into the live environment.
- An external USB or other backup of the existing age key (if you want to
  reuse the existing encrypted secrets — otherwise a fresh key is generated
  and you'll need to re-encrypt secrets afterwards).
- The target NVMe is `/dev/nvme0n1` (adjust if different).

### Steps

```bash
# 1. Clone the repo into the live environment
git clone https://github.com/mvrozanti/mandragora-nixos.git /tmp/mandragora
cd /tmp/mandragora

# 2. Partition + Btrfs subvolumes
sudo bash install/format-drive.sh /dev/nvme0n1

# 3. Mount the subvolumes for installation
sudo bash install/mount-install.sh

# 4. Get sops + age tools available in the live shell
nix shell nixpkgs#age nixpkgs#sops

# 5. Generate the age key and bootstrap secret encryption
sudo bash install/bootstrap-age-key.sh
#    - Prompts for the user 'm' password (also the login password).
#    - Writes the encrypted secrets file to secrets/secrets.yaml.
#    - Writes the age private key to /mnt/persistent/secrets/keys.txt.
#      *** BACK THIS KEY UP. Losing it locks you out of all secrets. ***

# 6. Run nixos-install
sudo bash install/install.sh

# 7. Reboot
reboot
```

After reboot, log in as `m` with the password set in step 5. The first boot
will trigger the impermanence wipe → snapshot cycle; subsequent boots are
clean.

### What Each Install Script Does

| Script                              | Responsibility                                                                    |
| ----------------------------------- | --------------------------------------------------------------------------------- |
| `install/format-drive.sh`           | Creates ESP, swap, Btrfs pool. Inside the pool: `root-blank`, `root-active`, `nix`, `persistent` subvolumes. |
| `install/mount-install.sh`          | Mounts subvolumes at `/mnt`, `/mnt/nix`, `/mnt/persistent`, etc., for the install. |
| `install/bootstrap-age-key.sh`      | Generates the age keypair, writes the private key to the persistent path, derives the public key, encrypts `secrets/secrets.yaml` against it. Prompts for the login password. |
| `install/install.sh`                | Runs `nixos-install --flake .#mandragora-desktop` against the mounted target.     |

### After First Boot

- Confirm impermanence is active: reboot once, verify that runtime files
  outside `/persistent` and `/home/m` are absent.
- Verify secrets decrypt: any service that depends on a sops secret should
  be running.
- Verify Hyprland session: log in, check NVIDIA + Wayland is functional.
- Run `modules/audits/strays.sh` once manually to confirm no unexpected
  state.

### Backup Critical Material

Two pieces of state are not in the repo and **cannot be regenerated**:

1. **Age private key** (`/persistent/secrets/keys.txt`) — without this, the
   sops-encrypted `secrets/secrets.yaml` is permanently unreadable. Back up
   to: external USB, Seafile, Oracle VPS.
2. **Wallpaper / theme source files** — if not in the repo, are not part of
   the declarative config and will be lost on reformat.

## Rollback / Recovery

| Failure mode                              | Recovery                                                                           |
| ----------------------------------------- | ---------------------------------------------------------------------------------- |
| Bad config switched in, system still boots | `sudo nixos-rebuild switch --rollback` or boot menu → previous generation         |
| Bad config, boot fails                    | systemd-boot menu → previous generation (up to 10 retained)                       |
| Disk failure                              | Replace disk, reinstall via [Fresh Install](#fresh-install), restore age key      |
| Lost age key                              | Secrets are unrecoverable; rotate every secret manually, regenerate, re-encrypt   |
| `/persistent` corruption                  | Restore from Btrfs snapshot if available; otherwise manual recovery                |

## CI / CD

There is no CI/CD pipeline. The single host is the only "production." This
is a deliberate choice for a single-user single-machine config — adding CI
would not catch failures the user doesn't already catch via empirical
verification on the actual hardware.

## Related Documents

- `../install/INSTALL.md` — the canonical install runbook
- `../atlas/PARTITION_PLAN.md` — disk layout design
- `./architecture.md` — system architecture (storage, impermanence, secrets)
- `./development-guide.md` — day-to-day rebuild workflow
- `./project-context.md` — _retired; pointer to AGENTS.md_

---

_Generated using BMAD Method `document-project` workflow._
