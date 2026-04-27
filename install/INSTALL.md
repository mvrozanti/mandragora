# Install Sequence

## Prerequisites
- NixOS live USB booted
- Internet connection (ethernet recommended)
- This repo cloned or copied to the live environment

## Steps

### 1. Clone the repo
```bash
git clone <your-repo> /tmp/mandragora
cd /tmp/mandragora
```

### 2. Partition the drive
```bash
sudo bash install/format-drive.sh /dev/nvme0n1
```

### 3. Mount subvolumes
```bash
sudo bash install/mount-install.sh
```

### 4. Get required tools
```bash
nix shell nixpkgs#age nixpkgs#sops
```

### 5. Generate age key and encrypt secrets
```bash
sudo bash install/bootstrap-age-key.sh
```
You will be prompted for a password for user `m`. This is your login password.

The encrypted secrets file is written to `secrets/secrets.yaml`. The age key lives at `/mnt/persistent/secrets/keys.txt` — **back this up somewhere safe**. Losing it locks you out of all secrets.

### 6. Install NixOS
```bash
sudo bash install/install.sh
```

### 7. Reboot
```bash
reboot
```

Log in as `m` with the password you set in step 5. The first boot triggers
the impermanence wipe → snapshot cycle; subsequent boots are clean.

---

## What each install script does

| Script                              | Responsibility                                                                    |
| ----------------------------------- | --------------------------------------------------------------------------------- |
| `install/format-drive.sh`           | Creates ESP, swap, Btrfs pool. Inside the pool: `root-blank`, `root-active`, `nix`, `persistent` subvolumes. |
| `install/mount-install.sh`          | Mounts subvolumes at `/mnt`, `/mnt/nix`, `/mnt/persistent`, etc., for the install. |
| `install/bootstrap-age-key.sh`      | Generates the age keypair, writes the private key to the persistent path, derives the public key, encrypts `secrets/secrets.yaml` against it. Prompts for the login password. |
| `install/install.sh`                | Runs `nixos-install --flake .#mandragora-desktop` against the mounted target.     |

## After first boot

- Confirm impermanence is active: reboot once, verify that runtime files
  outside `/persistent` and `/home/m` are absent.
- Verify secrets decrypt: any service that depends on a sops secret should
  be running.
- Verify Hyprland session: log in, check NVIDIA + Wayland is functional.
- Run `modules/audits/strays.sh` once manually to confirm no unexpected
  state.

## Backup critical material

Two pieces of state are not in the repo and **cannot be regenerated**:

1. **Age private key** (`/persistent/secrets/keys.txt`) — without this, the
   sops-encrypted `secrets/secrets.yaml` is permanently unreadable. Back up
   to: external USB, Seafile, Oracle VPS.
2. **Wallpaper / theme source files** — if not in the repo, they are not
   part of the declarative config and will be lost on reformat.

## Rollback / recovery

| Failure mode                              | Recovery                                                                           |
| ----------------------------------------- | ---------------------------------------------------------------------------------- |
| Bad config switched in, system still boots | `sudo nixos-rebuild switch --rollback` or boot menu → previous generation         |
| Bad config, boot fails                    | systemd-boot menu → previous generation (up to 10 retained)                       |
| Disk failure                              | Replace disk, reinstall via the steps above, restore age key from backup          |
| Lost age key                              | Secrets are unrecoverable; rotate every secret manually, regenerate, re-encrypt   |
| `/persistent` corruption                  | Restore from Btrfs snapshot if available; otherwise manual recovery                |

## CI / CD

There is no CI/CD pipeline. The single host is the only "production." This
is a deliberate choice for a single-user single-machine config — adding CI
would not catch failures the user doesn't already catch via empirical
verification on the actual hardware.

---

