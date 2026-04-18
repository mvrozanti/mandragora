# Ventoy USB — Developer Reference

The Mandragora Ventoy USB is a multiboot rescue/installation drive.
Boot into Arch or NixOS with tools, persistence, and the full NixOS flake.

## USB Layout (after `create-ventoy-usb.sh`)

```
/
├── isos/
│   ├── mandragora-arch.iso
│   └── mandragora-nixos.iso
├── persistence/
│   ├── arch_persistence.dat      2GB ext4, Ventoy cow persistence
│   └── nixos_persistence.dat     2GB ext4, Ventoy cow persistence
├── ventoy/
│   └── ventoy.json               Boot config, persistence mapping, menu aliases
├── toolbox/
│   ├── format-drive.sh           Partition + format + mount target disk
│   ├── hw-diag.sh                Full hardware diagnostics
│   └── gpu-stress.sh             GPU stress test menu
├── docs/
│   └── mandragora-nixos/         Full flake repo (copied by create-ventoy-usb.sh)
└── keys/                         Age keys, secrets (user-managed)
```

## Building

### 1. Build custom ISOs (optional — falls back to stock downloads)

```bash
sudo ./build-iso.sh
```

Needs `archiso` (Arch) and/or `nix` (NixOS) on the host. Stock ISOs work fine.

### 2. Create the USB

```bash
sudo ./create-ventoy-usb.sh /dev/sdX
```

Installs Ventoy, copies ISOs, creates persistence images, copies toolbox + flake repo.

### 3. Building the NixOS ISO from Arch

The custom NixOS ISO requires the `nix` package manager. It coexists with pacman —
uses its own `/nix` store, doesn't interfere with anything.

```bash
# install nix (one-time, multi-user daemon)
sh <(curl -L https://nixos.org/nix/install) --daemon
# open a new shell to pick up nix in PATH

# build the ISO
nix build ./nixos-iso#nixosConfigurations.mandragora-usb.config.system.build.isoImage \
    --extra-experimental-features "nix-command flakes"

# ISO is at result/iso/mandragora-nixos-*.iso
cp result/iso/mandragora-nixos-*.iso ~/iso_cache/mandragora-nixos.iso
```

### 4. Updating an existing USB

**Quick update** (toolbox scripts + repo only, no ISO rebuild):

```bash
sudo mount /dev/sdX1 /mnt
sudo cp toolbox/*.sh /mnt/toolbox/ && sudo chmod +x /mnt/toolbox/*.sh
sudo rm -rf /mnt/docs/mandragora-nixos && sudo cp -a ../.. /mnt/docs/mandragora-nixos
sudo umount /mnt
```

This gets you the latest format-drive.sh and repo, but the live boot environment
stays unchanged (stock ISO, no flakes, no sops/age pre-installed).

**Full update** (rebuild ISO + update everything):

```bash
# 1. build the custom NixOS ISO (see step 3 above)
nix build ./nixos-iso#nixosConfigurations.mandragora-usb.config.system.build.isoImage \
    --extra-experimental-features "nix-command flakes"

# 2. mount the USB
sudo mount /dev/sdX1 /mnt

# 3. replace the ISO
sudo cp result/iso/mandragora-nixos-*.iso /mnt/isos/mandragora-nixos.iso

# 4. update toolbox + repo
sudo cp toolbox/*.sh /mnt/toolbox/ && sudo chmod +x /mnt/toolbox/*.sh
sudo rm -rf /mnt/docs/mandragora-nixos && sudo cp -a ../.. /mnt/docs/mandragora-nixos

# 5. done
sudo umount /mnt
```

The full update gives you: flakes enabled, sops+age pre-installed, ~/README.md on
login, AI tools auto-install, zsh+tmux shell — the complete experience.

## Files

| File | Purpose |
|------|---------|
| `create-ventoy-usb.sh` | Formats USB with Ventoy, copies everything |
| `build-iso.sh` | Builds custom Arch + NixOS ISOs |
| `ventoy.json` | Ventoy config: ISO paths, persistence mapping, menu aliases |
| `nixos-iso/configuration.nix` | NixOS live ISO system config |
| `nixos-iso/flake.nix` | NixOS ISO flake wrapper |
| `nixos-iso/root-dotfiles/` | Dotfiles + README placed in /root on boot |
| `archiso/` | Arch ISO overlay: packages, dotfiles, profile scripts |
| `archiso/packages-extra.txt` | Extra packages merged into Arch releng profile |
| `toolbox/` | Scripts shipped on the USB at `/mnt/ventoy/toolbox/` |

## The Boot Experience

1. Power on, hold boot menu key, select USB
2. Ventoy menu: pick "Arch Linux — Mandragora" or "NixOS — Mandragora"
3. Live shell opens: zsh + tmux, MOTD with available commands
4. `cat ~/README.md` — full step-by-step install guide
5. `/mnt/ventoy` auto-mounted read/write (the USB's exFAT partition)
6. Flake at `/mnt/ventoy/docs/mandragora-nixos`
7. `nix shell`, `nix build`, `sops`, `age` all work without extra flags

## Persistence

Ventoy persistence images keep changes between boots within the same ISO session.
npm global installs, shell history, config edits persist automatically.

The persistence images are created by `create-ventoy-usb.sh` (default 2GB each).
To increase: change `ARCH_PERSIST_MB` / `NIXOS_PERSIST_MB` at the top of the script.

## Key Design Decisions

- **NixOS is the primary path.** Arch is there as a fallback with broader hardware support.
- **`nix.settings.experimental-features`** enabled in the ISO config so nix commands just work.
- **`sops` + `age`** are system packages — no `nix shell` needed for secrets setup.
- **AI tools** (claude, gemini, qwen) install via npm on first boot with network.
- **`format-drive.sh`** does the full pipeline: partition, format, subvolumes, mount, copy flake, generate hw config.
