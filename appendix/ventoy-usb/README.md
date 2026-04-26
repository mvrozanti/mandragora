# Ventoy USB — Developer Reference

The Mandragora Ventoy USB is a multiboot rescue/installation drive.
Boot into Arch or NixOS with tools, persistence, and the full NixOS flake.

## USB Layout (after `create-ventoy-usb.sh`)

```
/
├── isos/
│   ├── mandragora-arch.iso
│   └── mandragora.iso
├── persistence/
│   ├── arch_persistence.dat      2GB ext4, Ventoy cow persistence (Arch)
│   └── nixos_persistence.dat     2GB ext4, loop-mounted at /persist (NixOS)
├── ventoy/
│   └── ventoy.json               Boot config, persistence mapping, menu aliases
├── toolbox/
│   ├── format-drive.sh           Partition + format + mount target disk
│   ├── hw-diag.sh                Full hardware diagnostics
│   └── gpu-stress.sh             GPU stress test menu
├── docs/
│   └── mandragora/         Full flake repo (copied by create-ventoy-usb.sh)
└── keys/                         Age keys, secrets (user-managed)
```

## Building

### 1. Build custom ISOs

```bash
sudo ./build-iso.sh
```

Builds both Arch and NixOS ISOs. The NixOS build tries: native nix → Docker → stock download.
On Arch without nix installed, Docker is the primary path (requires `docker` running).

### 2. Create the USB

```bash
sudo ./create-ventoy-usb.sh /dev/sdX
```

Installs Ventoy, copies ISOs, creates persistence images, copies toolbox + flake repo.

### 3. Updating an existing USB

```bash
sudo ./build-iso.sh                    # rebuild ISOs
sudo ./update-usb.sh /dev/sdX         # push everything to USB
```

`update-usb.sh` copies: ISO, toolbox scripts, ventoy.json, repo, and
Claude credentials + SSH keys into the NixOS persistence image.

## Files

| File | Purpose |
|------|---------|
| `create-ventoy-usb.sh` | Formats USB with Ventoy, copies everything |
| `update-usb.sh` | Updates existing USB: ISOs, toolbox, repo, credentials |
| `build-iso.sh` | Builds custom Arch + NixOS ISOs (nix, docker, or stock) |
| `ventoy.json` | Ventoy config: ISO paths, persistence mapping, menu aliases |
| `nixos-iso/configuration.nix` | NixOS live ISO system config |
| `nixos-iso/flake.nix` | NixOS ISO flake wrapper |
| `nixos-iso/root-dotfiles/` | Dotfiles + README placed in /home/nixos and /root on boot |
| `archiso/` | Arch ISO overlay: packages, dotfiles, profile scripts |
| `archiso/packages-extra.txt` | Extra packages merged into Arch releng profile |
| `toolbox/` | Scripts shipped on the USB at `/mnt/ventoy/toolbox/` |

## The Boot Experience

1. Power on, hold boot menu key, select USB
2. Ventoy menu: pick "Arch Linux — Mandragora" or "NixOS — Mandragora"
3. Live shell opens: zsh, MOTD with available commands
4. `cat ~/README.md` — full step-by-step install guide
5. `/mnt/ventoy` auto-mounted read/write (the USB's exFAT partition)
6. Flake at `/mnt/ventoy/docs/mandragora`
7. `nix shell`, `nix build`, `sops`, `age` all work without extra flags

## NixOS Persistence

`nixos_persistence.dat` is an ext4 image loop-mounted at `/persist` by the
`mount-persist` systemd service on boot. It stores:

- `/persist/npm-global/` — npm global installs (claude, gemini, qwen) survive reboots
- `/persist/claude/` — Claude OAuth credentials (symlinked to ~/.claude/)
- `/persist/ssh/` — SSH keys (symlinked to ~/.ssh/)
- `/persist/zsh-history/` — shell history

Credentials and SSH keys are copied into the persist image by `update-usb.sh`.
Ventoy cow persistence is used for Arch only (not NixOS).

## Claude Authentication

Claude Code authenticates via a long-lived OAuth token baked into the ISO.

### Setup (one-time)

    claude auth oauth-token --long-lived

Save the token, then:

    echo "export CLAUDE_CODE_OAUTH_TOKEN='sk-ant-...'" > appendix/ventoy-usb/nixos-iso/root-dotfiles/.claude_env

Rebuild the ISO for it to take effect. The file is gitignored (contains a secret).

### How it works

`.claude_env` follows the same path as `.bash_aliases`:

    environment.etc → /etc/skel/.claude_env → provision-dotfiles → ~/.claude_env → shell init sources it

No mounts, no symlinks, no timing dependencies. The token is part of the ISO.

### Rotating the token

Generate a new token, overwrite `.claude_env`, rebuild the ISO, update the USB.

## NixOS Dotfile Delivery

Dotfiles (README.md, .zshrc, .tmux.conf, .claude_env, etc.) are placed in
`/etc/skel/` via `environment.etc` and copied to user homes by the
`provision-dotfiles` systemd service before login. Shell init has a fallback
copy mechanism.

If dotfiles don't appear on boot, check the service log:

    journalctl -u provision-dotfiles --no-pager

## Key Design Decisions

- **NixOS is the primary path.** Arch is there as a fallback with broader hardware support.
- **`nix.settings.experimental-features`** enabled in the ISO config so nix commands just work.
- **`sops` + `age`** are system packages — no `nix shell` needed for secrets setup.
- **AI tools** (claude, gemini, qwen) install via npm on first boot with network.
- **`format-drive.sh`** does the full pipeline: partition, format, subvolumes, mount, copy flake, generate hw config.
