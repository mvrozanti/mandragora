# Mandragora USB + Refiner — Design Spec

**Date:** 2026-04-25
**Status:** Proposed
**Author:** m + Claude (brainstorming session)

## Summary

Three coupled changes to the Mandragora flake:

1. **Promote the live USB to a first-class NixOS host.** `appendix/ventoy-usb/nixos-iso/configuration.nix` is retired; a new `hosts/mandragora-usb/` declares `nixosConfigurations.mandragora-usb`. The side-flake at `appendix/ventoy-usb/nixos-iso/flake.nix` is deleted.
2. **Replace the Ventoy multiboot USB with a single writable disk image.** Built via `nixos-generators -f raw-efi`, flashed with `dd`, hardware-agnostic, console-only.
3. **Add a refiner test harness as a flake app.** `nix run .#refiner` boots the USB image in QEMU with a blank target disk attached so the install pipeline can be exercised iteratively without touching real hardware.

The ventoy + Arch ISO + persistence-`.dat` + custom archiso overlay machinery is removed entirely. Iteration time, build complexity, and surface area all shrink.

## Goals

- Mandragora USB is a portable installer that runs on any UEFI x86_64 machine, drops the user into a familiar zsh + tmux + nvim environment with claude/gemini available, and installs a clean Mandragora system onto a target disk.
- Iterating on USB contents (install scripts, host config, shared modules) does not require flashing a real USB; `nix run .#refiner` is the daily test path.
- Both `mandragora-desktop` and `mandragora-usb` share modules. The desktop is unaffected by the refactor when the work is complete.
- Failure modes that matter on real hardware (wrong target disk, stale flake, missing microcode) are caught by the install pipeline before damage occurs.

## Non-goals

- A graphical desktop environment on the USB. Console-only.
- Gaming, media production, NVIDIA proprietary drivers, Steam, or any compositor effects.
- Real-hardware variance testing in CI: Secure Boot, BIOS-only, NVIDIA RTX with nouveau, captive-portal Wi-Fi, HiDPI rendering. Manually verified before v1.
- Dual-boot install mode, FDE/LUKS2/TPM2, persistence partition resizing. Argument shape kept where reasonable; implementation deferred to v2.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                  /etc/nixos/mandragora (main flake)                  │
│                                                                      │
│  ┌──────────────────────────┐   ┌──────────────────────────────┐   │
│  │ hosts/mandragora-desktop │   │ hosts/mandragora-usb         │   │
│  │  (profile = "desktop")    │   │  (profile = "live")          │   │
│  └──────┬───────────────────┘   └──────┬───────────────────────┘   │
│         │  imports                     │  imports                   │
│         └──────────┬──────────────────┘                             │
│                    │                                                │
│            ┌───────▼──────────┐                                     │
│            │ modules/*.nix    │  shared modules with               │
│            │ (zsh, nvim,      │  mandragora.profile enum gating    │
│            │  sops, network…) │                                    │
│            └──────────────────┘                                     │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ refiner/                                                      │  │
│  │   default.nix         flake app: writeShellApplication       │  │
│  │   run-vm.sh           qemu + OVMF + USB image + target disk  │  │
│  │   auto-install.sh     scripted single-shot smoke check       │  │
│  │   lib.sh              state-dir, KVM check, OVMF NVRAM copy  │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘

Build outputs:
  nix build .#packages.x86_64-linux.usbImage         → result/.../usb.img
  nix run   .#refiner [--fresh] [--auto] [--scenario] → launches QEMU

Runtime state (refiner):
  /home/m/Projects/mandragora-usb-refiner/
    state/
      target.qcow2          blank install target, recreated each run (~40 GB sparse)
      OVMF_VARS.fd          per-run NVRAM copy, recreated each run
      run-NNN.log           QEMU + serial logs

The USB image itself is never copied to state. QEMU attaches it via
`-drive file=…/usb.img,if=virtio,snapshot=on`; writes go to an in-memory
overlay that is discarded on VM shutdown. Every run starts from pristine.
```

### Three load-bearing seams

1. **Host ↔ shared modules.** Each shared module declares `options.mandragora.profile : enum [ "desktop" "live" ]` and gates fields with `lib.mkIf (cfg.profile == "live")` (or `"desktop"`). `mandragora-desktop` sets profile to `"desktop"` (default), `mandragora-usb` sets profile to `"live"`. Live-mode strips: NVIDIA env, monitor pins, mpd, keyleds, kdeconnect, btrfs/impermanence assumptions. Live-mode adds: `/persist` partition mount, npm-global env, claude-bootstrap.service, install entrypoints.

2. **Host → image.** `nixos-generators` produces the raw-efi disk image from the USB host's `nixosConfiguration`. Single Nix derivation. Output is content-addressed; rebuilds are incremental.

3. **Image → refiner.** Refiner is a flake app that takes the image path as a Nix-resolved dependency and attaches it to QEMU as `virtio-blk` with `snapshot=on` (no copy; overlay in memory; pristine each run). Target disk and OVMF NVRAM are recreated in state-dir on every run. There is no "preserve state across runs" mode in MVP.

## Components

### `hosts/mandragora-usb/default.nix` (new)

Built **fresh**, not lifted from the existing 509-line `nixos-iso/configuration.nix`. Imports shared modules with `mandragora.profile = "live"`. Adds:

- `/persist` partition mount (ext4, label `mandragora-persist`)
- `npm_config_prefix = "/persist/npm-global"`, PATH includes `/persist/npm-global/bin`
- `claude-bootstrap.service`: systemd oneshot, on-failure-OK, runs `npm install -g @anthropic-ai/claude-code @google/gemini-cli @qwenlm/qwen-cli` if not already in `/persist/npm-global/bin/`. Idempotent. Skips if offline.
- Install entrypoints on PATH: `mandragora-install`, `mandragora-detect`, `mandragora-format`
- MOTD with quick-start instructions
- Dotfile delivery via `environment.etc → /etc/skel` + `provision-dotfiles.service` (preserved from existing)
- The encrypted age key for the USB host at `/etc/sops/usb-key.age`
- Linux-firmware (Wi-Fi/BT chips that need it)
- networkmanager + nmtui for offline Wi-Fi setup
- Console-only: no display manager, no compositor, no Mesa userspace beyond what kernel needs for KMS

Cherry-pick from old config only after M3 works; treat the old file as reference, not source.

### `hosts/mandragora-usb/install/` (new)

Pipeline scripts, all referenced from Nix via `pkgs.writeShellApplication` per Language Purity:

| Script | Responsibility |
|---|---|
| `lib.sh` | Logging helpers, root check, confirmation prompts |
| `detect.sh` | Identify boot media (resolve `/proc/cmdline → root=` to by-id), enumerate non-boot block devices, refuse if only the boot disk exists |
| `format.sh` | sgdisk: ESP (1 GB FAT32) + root (rest, ext4 by default). Mounts under `/mnt`. Refuses if disk < 30 GB. Requires `WIPE` confirmation if existing partitions found |
| `render-config.sh` | Generates hardware-config + a starter `hosts/<hostname>/default.nix` from a template, filled with: detected CPU vendor microcode, GPU vendor (intel/amd/nouveau/none), filesystem profile |
| `install.sh` | Orchestrator. Tries `git -C /mnt/etc/nixos/mandragora pull origin main` if network. Calls `detect → prompts → format → render → nixos-install --flake /mnt/etc/nixos/mandragora#<hostname>`. Decrypts `secrets/usb-key.age` via passphrase prompt; copies decrypted key to `/mnt/persistent/sops/`. Re-prompts up to 3× on bad passphrase, proceeds without sops on final failure with explicit warning |

### `modules/*.nix` (refactored)

Each shared module gains the profile enum:

```nix
{ config, lib, ... }: let cfg = config.mandragora; in {
  options.mandragora.profile = lib.mkOption {
    type = lib.types.enum [ "desktop" "live" ];
    default = "desktop";
  };
  config = lib.mkMerge [
    (lib.mkIf (cfg.profile == "desktop") { /* desktop-only */ })
    { /* always-on */ }
  ];
}
```

Modules that need refactoring:
- `modules/desktop/hyprland.nix` — desktop-only entirely (live profile excludes Hyprland)
- `modules/desktop/waybar.nix` — desktop-only entirely
- `modules/user/home.nix` — gate mpd, keyleds, kdeconnect, all desktop-flavor home-manager pieces
- `modules/core/impermanence.nix` — gate the entire module on desktop
- `modules/core/globals.nix` — review for hidden assumptions; most should be always-on

Modules untouched (already cross-profile): zsh, tmux, nvim, sops, networking, sshd.

### `refiner/` (new)

A flake app at `apps.x86_64-linux.refiner`. `default.nix` wraps `run-vm.sh` and `auto-install.sh` via `pkgs.writeShellApplication`, declaring runtime deps (`qemu_kvm`, `OVMF`, `coreutils`, `util-linux`, `e2fsprogs`, `dosfstools`, `expect`).

`run-vm.sh`:
- Sources `lib.sh` for state-dir layout, KVM check, OVMF NVRAM copy, target-disk allocation, run-number
- Resolves USB image path from `$1` or env (`MANDRAGORA_USB_IMG`, defaulted by `default.nix` via `${self.packages.x86_64-linux.usbImage}/usb.img`)
- Recreates `state/target.qcow2` (40 GB sparse) each run via `qemu-img create`
- Recreates `state/OVMF_VARS.fd` each run by copying from `${OVMF}/share/OVMF/OVMF_VARS.fd`
- Invokes QEMU: OVMF + USB image attached as `-drive file=…,if=virtio,snapshot=on` (overlay in memory, no on-disk writable copy) + target virtio-blk + virtio-net user-mode + virtio-rng + 6 GB RAM + 4 vCPU + `-display none -serial stdio`
- Logs QEMU output to `state/run-NNN.log`

`auto-install.sh`:
- Boots the VM with serial console
- Drives install via `expect`: `mandragora-install --auto --hostname mandragora-test --user m --target /dev/vdb --scheme plain --gpu intel --keymap us --sops-passphrase "$REFINER_TEST_PASSPHRASE"`
- Waits for install (30-min wall-clock cap)
- Reboots VM with USB removed, target disk as boot device
- Verifies: `systemctl is-system-running ∈ {running, degraded}`, `id m` succeeds
- On failure: captures `state/failed-NNN.qcow2` for inspection, returns non-zero

`lib.sh`:
- `mkdir -p state/`
- Refuse if `[[ -r /dev/kvm && -w /dev/kvm ]]` is false, with "add user to `kvm` group" message
- Warn if `/proc/meminfo` shows < 12 GB free
- Allocate run number (`state/run-$(date +%Y%m%d-%H%M%S)-$$.log`)

### `pkgs/` (no AI tool packaging)

Decision: AI tools install via npm at first boot into `/persist/npm-global/`. No `buildNpmPackage` work in MVP. Re-evaluate when one of the tools lands in nixpkgs.

### `secrets/usb-key.age` (new)

Passphrase-encrypted (`age -p`) age private key for the USB host. Decrypts only USB-host-specific sops files; cannot decrypt desktop secrets. Baked into the USB closure at `/etc/sops/usb-key.age`. Decrypted at install time after passphrase prompt, copied to target system's `/persistent/sops/`.

`.sops.yaml` updated to declare a USB-host recipient:

```yaml
keys:
  - &m_desktop age1...
  - &m_usb age1...
creation_rules:
  - path_regex: secrets/desktop-.*\.yaml$
    key_groups: [{ age: [*m_desktop] }]
  - path_regex: secrets/usb-.*\.yaml$
    key_groups: [{ age: [*m_usb] }]
```

Blast radius if USB is lost and passphrase eventually cracked: USB-only secrets. Desktop secrets unaffected.

### `flake.nix` changes

- Add `nixos-generators` input
- Add `nixosConfigurations.mandragora-usb`
- Add `packages.x86_64-linux.usbImage = nixos-generators.nixosGenerate { format = "raw-efi"; ... }`
- Add `apps.x86_64-linux.refiner = { type = "app"; program = "${refiner-pkg}/bin/refiner"; }`

## Data Flow

### A. Daily iteration in the refiner

```
edit hosts/mandragora-usb/install/format.sh (or any shared module)
   │
   ▼
nix run .#refiner
   │  1. nix build .#usbImage              ── Nix figures out incremental rebuild
   │     ↳ /nix/store/.../usb.img
   │  2. recreate state/OVMF_VARS.fd       (per-run NVRAM copy)
   │  3. recreate state/target.qcow2       (40 GB sparse, blank)
   │  4. qemu-system-x86_64 \
   │       -bios OVMF_CODE -drive ovmf-vars \
   │       -drive file=usb.img,if=virtio,snapshot=on \
   │       -drive file=target.qcow2,if=virtio \
   │       -display none -serial stdio
   ▼
serial → terminal: login prompt, user runs mandragora-install
```

Rebuild scope by edit:
- toolbox script → host's `writeShellApplication` rebuilds → image repacks → ~30 sec
- shared module → modules importing it rebuild → image repacks → 1–3 min
- new system package → fetch + maybe build → image repacks
- nothing changed → `nix build` no-op; refiner just boots cached image

### B. Real USB flash

```
nix build .#usbImage           result/sd-image/usb.img
sudo dd if=…/usb.img of=/dev/sdX bs=4M status=progress oflag=direct
sync
                               16 GB USB now bootable on real hardware
```

Same `usb.img` artifact feeds the refiner and the real flash.

### C. Install onto a target machine (real or VM)

```
boot USB / VM
  ↓
console login as m
  ↓
$ mandragora-install
  ↓
  install.sh:
    - if network up: git -C /mnt/etc/nixos/mandragora pull origin main || true
    - prompt: hostname (default mandragora-$(short-uuid)), user (default m),
              keyboard layout (default us),
              filesystem profile (plain = single ext4 root, no subvolumes, no impermanence),
              GPU driver (detected value shown; user accepts default or overrides),
              encryption (none for v1)
    - prompt: sops passphrase → age -d secrets/usb-key.age (3 retries)
  ↓
  detect.sh:
    - resolve /proc/cmdline root= → boot media by-id
    - enumerate /sys/block, exclude boot media, exclude removable
    - refuse if no candidate target
    - present interactive select (no default)
    - if target has existing partitions: print layout, require WIPE confirmation
  ↓
  format.sh:
    - refuse if disk < 30 GB
    - sgdisk: ESP (1 GB FAT32) + root (rest, ext4)
    - mkfs, mount under /mnt
  ↓
  render-config.sh:
    - nixos-generate-config --root /mnt --no-filesystems
    - render hosts/<hostname>/default.nix from template:
        cpu microcode = intel-ucode | amd-ucode (from /proc/cpuinfo)
        gpu driver = intel | amdgpu | nouveau | none (from lspci)
        filesystem profile = plain
    - copy decrypted age key to /mnt/persistent/sops/
  ↓
  nixos-install --flake /mnt/etc/nixos/mandragora#<hostname>
  ↓
  reboot → user removes USB → boots target disk → mandragora-<hostname>
```

Two safety properties:
- **Cannot install onto the boot media** — `detect.sh` filters by-id and refuses if the only candidate left is empty
- **Cannot wipe a disk silently** — `format.sh` shows existing partitions and requires `WIPE`-typed confirmation

## Iteration Workflow

**Fast path (90% of edits):** edit shared module / install script / host config → `nix run .#refiner` → Nix rebuilds incrementally → VM boots with new contents.

**Slow path:** first build, or whenever a foundational dependency changes (nixpkgs bump, kernel change). 5–10 min.

No 9p / virtio-fs / overlay-from-source machinery in MVP. If iteration becomes painful in practice, this is the lever to revisit. YAGNI until proven otherwise.

## Phasing (vertical slice)

| # | Milestone | Exit check |
|----|-----------|-----------|
| M1 | **Minimal USB host + raw-efi build + flash to a real 16 GB USB and boot one machine.** Promote to host (fresh, not lifted), add `nixos-generators` input, add `packages.usbImage`. Strip to: zsh, tmux, nvim, git, sops, age, openssh, nmtui, install scripts. No shared modules yet (inline). Real-hardware boot is a hard exit gate. | `nix build .#usbImage` succeeds; manual `qemu` boots to login; physical USB also boots one machine to login |
| M2 | **Refiner harness.** `refiner/run-vm.sh` + flake app with state-dir, KVM check, OVMF NVRAM copy, target disk allocation, QEMU invocation. Pure serial, no GUI. | `nix run .#refiner` boots M1 image, two virtio disks visible (`/dev/vda` USB, `/dev/vdb` blank) |
| M3 | **Install pipeline minimal + git-pull-before-install.** `install/{lib,detect,format,render-config,install}.sh`. For MVP: `--scheme plain`, no encryption, prompts for hostname/user/keymap. | In refiner: `mandragora-install` partitions `/dev/vdb`, installs from in-USB flake, manual reboot of VM into target boots successfully |
| M4 | **Shared modules with `profile` enum.** Refactor zsh and nvim modules first (smallest surface). USB host switches to `imports = [ ../shared/zsh.nix ../shared/nvim.nix ]` with `mandragora.profile = "live"`. Build desktop and USB image both. | Desktop still rebuilds; USB image still builds; both have zsh+nvim configured identically |
| M5 | **First-boot npm + `claude-bootstrap.service`.** `npm_config_prefix = "/persist/npm-global"`, PATH update, systemd oneshot service installs claude/gemini/qwen if absent. Idempotent. | Fresh VM with network: after first boot, `claude --version`, `gemini --version`, `qwen --version` all succeed; second boot doesn't reinstall |
| M6 | **DELETED.** GUI dropped from MVP per design discussion | n/a |
| M7 | **Sops with USB-specific age key.** `secrets/usb-key.age` passphrase-encrypted; `.sops.yaml` declares USB recipient; install step decrypts and places into target. | Target system after install can `sops -d` a USB-recipient secret; cannot decrypt a desktop-recipient secret |
| M8 | **Install hardening.** Boot-media self-detection refusal; multi-disk safe selection in `detect.sh`; CPU microcode + GPU driver detection in `render-config.sh`; keyboard layout prompt; explicit `WIPE` confirmation for non-empty disks. | In refiner with two virtio target disks: `detect.sh` shows both, refuses if user picks the boot media; `--small-target` scenario fails appropriately |
| M9 | **`--auto` smoke test.** `auto-install.sh` drives install non-interactively via expect. Reboots VM, verifies `systemctl is-system-running` + `id m`. | `nix run .#refiner -- --auto` returns 0 on success, captures logs to `state/run-NNN.log` |

**Critical-path observation:** M1–M3 are the load-bearing slice. Once those work, you have a working USB-in-VM and a working install. M4–M9 are *expansion*. v0.1 is shippable at M3.

## Error Handling and Edge Cases

### Install pipeline (highest stakes — wrong here = data loss)

| Failure mode | Detection | Response |
|---|---|---|
| Boot media is the only/selected target disk | `detect.sh` resolves `/proc/cmdline → root=` against candidates by-id | Refuse; exit non-zero |
| Multiple disks, no explicit choice | `detect.sh` enumerates non-boot block devices | Force interactive select; no default |
| Selected target has existing partitions | `lsblk` shows partitions on target | Print layout, require `WIPE`-typed confirmation |
| `nixos-install` fails midway | exit code | Leave `/mnt` mounted, print log path; user can chroot to fix |
| Sops passphrase wrong | `age -d` non-zero | Re-prompt up to 3×; final failure proceeds without sops with explicit warning |
| Network down during install (with stale baked flake) | git pull fails or no network | Best-effort pull skipped; proceed with baked flake; warn in log |
| Disk too small | `lsblk -bno SIZE` < 30 GB | Refuse; warn at < 60 GB |

### Live system

| Failure mode | Detection | Response |
|---|---|---|
| `/persist` partition missing or corrupt | systemd mount unit fails | Continue boot with tmpfs; warn on login MOTD |
| Wi-Fi card needs nonfree firmware | `nmcli device` shows no wlan | linux-firmware should cover; if not, document workaround |
| Time skew breaks TLS | NTP retry log | chrony with multiple sources; print "set the clock manually" if skew persists |
| First-boot `claude-bootstrap.service` offline | exit non-zero | Service is `Type=oneshot`, `RemainAfterExit=no`, runs again on next boot until success |

### Refiner

| Failure mode | Detection | Response |
|---|---|---|
| `/dev/kvm` not accessible | `lib.sh` check | Refuse with "add user to `kvm` group" message |
| Host < 12 GB free RAM | `free -m` check | Warn; allow override with `--ram <MB>` |
| OVMF NVRAM copy missing | check before launch | Auto-create from `${OVMF_VARS}` |
| Target disk locked by stale qemu | qcow2 lock | Fail; suggest `--fresh` |
| QEMU exits non-zero | wait status | Print last 200 lines of `state/run-NNN.log` |
| `--auto` install timeout (30 min cap) | wall-clock | Kill QEMU, dump logs, return non-zero |
| `--auto` smoke check fails | post-reboot serial | Capture full target disk to `state/failed-NNN.qcow2`; return non-zero |

### Build pipeline

| Failure mode | Response |
|---|---|
| `nixos-generators` build fails | Standard Nix error; no special handling |
| Closure exceeds practical USB size | Build-time guard fails build if USB host closure > 6 GiB (see Testing → Build-time checks for rationale) |
| Hyprland config errors (desktop only after refactor) | `hyprland --check-config` derivation; fail build on any error |

### Out-of-scope edge cases (deferred to v2)

- Secure Boot enforcement (needs lanzaboote)
- Legacy BIOS-only machines (raw-efi is UEFI-only)
- Dual-boot install mode (`--mode coexist`)
- LUKS2 / TPM2 encryption
- Persistence partition resize after flash
- Windows ESP reuse

Argument shape kept where reasonable (`--encrypt none|luks2`, `--mode wipe|coexist`) so v2 doesn't break v1 calling conventions.

## Testing (automatable only)

The refiner *is* the test harness. Same QEMU invocation, different scenarios.

### Build-time checks

- `hyprland --check-config` against rendered desktop config — build fails on any error
- USB host closure size: `nix path-info -Sh .#nixosConfigurations.mandragora-usb.config.system.build.toplevel` against a 6 GiB ceiling. (Closure ≈ partition − filesystem overhead; 6 GiB closure leaves room for a ~7–8 GiB ext4 root in the raw-efi image, comfortable on a 16 GB stick after ESP and `/persist`.)
- Each shared module evaluated under both `profile = "desktop"` and `profile = "live"` — both must succeed
- `secrets/usb-key.age` asserted to start with `-----BEGIN AGE ENCRYPTED FILE-----`, never plaintext

### Refiner scenarios

| Scenario | QEMU change | Asserts |
|---|---|---|
| `--smoke` | default | console login appears within 60 s |
| `--auto` | + scripted serial input | install + reboot + `systemctl is-system-running` ∈ {running, degraded} + `id m` |
| `--multi-disk` | extra `-drive` virtio disks | `detect.sh` enumerates all non-boot disks, refuses if user picks boot media |
| `--small-target` | 10 GB target.qcow2 | `format.sh` refuses with "disk too small" exit code |
| `--no-network` | `-netdev none` | install succeeds with baked flake (proves closure is fully cached on USB) |
| `--clock-skew` | `-rtc base=2010-01-01` | chrony recovers within 60 s; install does not fail on TLS |
| `--bad-passphrase` | scripted: feed wrong sops passphrase 3× | install completes; `/mnt/persistent/sops/` empty; warning in install log |

Pass/fail is the harness exit code. Logs at `state/run-NNN.log`.

### Not in scope (explicitly)

Real-hardware variance — Secure Boot, BIOS-only, NVIDIA RTX, captive-portal Wi-Fi, HiDPI rendering — is not testable from this dev machine. Documented as "verify on real hardware before declaring v1 done." Real-hardware bugs become regression scenarios only if reproducible in QEMU.

## Suspicious Assumptions (acknowledged)

Risks identified during brainstorming, with mitigations baked into the design:

| # | Assumption | Mitigation in design |
|---|---|---|
| 1 | `nixos-generators` raw-efi is directly USB-bootable | M1 exit gate requires real-hardware boot, not just QEMU |
| 2 | Disk image fits on a 16 GB stick | Console-only Tier 2 closure ≈ 4–5 GiB; image ≈ 6 GiB; 9 GB headroom for `/persist` |
| 3 | Hyprland in QEMU works | GUI dropped from MVP; refiner is pure serial |
| 4 | `buildNpmPackage` for AI tools | Replaced with first-boot npm into `/persist/npm-global` + idempotent service |
| 5 | Greetd graceful fallback | GUI dropped; moot |
| 6 | Sops passphrase encryption is "good enough" | USB has its own age recipient; blast radius limited to USB-only secrets |
| 7 | In-USB flake stale at install | `git pull origin main` best-effort before install |
| 8 | `liveMode` boolean grows spaghetti | Replaced with `profile` enum |
| 9 | Refactoring desktop modules is safe | Discipline: every module change must `nixos-rebuild build` (USB and desktop) before `switch` |
| 10 | Existing 509-line config lifts cleanly | Build host fresh, cherry-pick from old config only after M3 works |

## Open Questions (none blocking)

None at this time. Ready for implementation planning.

## File Inventory (final)

Created:
- `hosts/mandragora-usb/default.nix`
- `hosts/mandragora-usb/install/{lib,detect,format,render-config,install}.sh`
- `hosts/mandragora-usb/diagnostics/{hw-diag,gpu-stress}.sh` (cherry-picked from old toolbox)
- `refiner/{default.nix,run-vm.sh,auto-install.sh,lib.sh}`
- `secrets/usb-key.age`
- `docs/superpowers/specs/2026-04-25-mandragora-usb-refiner-design.md` (this file)

Modified:
- `flake.nix` — add input, host, package, app
- `.sops.yaml` — add USB recipient
- `modules/desktop/hyprland.nix` — desktop-only
- `modules/desktop/waybar.nix` — desktop-only
- `modules/user/home.nix` — gate desktop-flavor pieces
- `modules/core/impermanence.nix` — desktop-only
- `modules/core/globals.nix` — review
- `modules/shared/zsh.nix` — add profile enum (M4)
- `modules/shared/nvim.nix` — add profile enum (M4)

Deleted:
- `appendix/ventoy-usb/nixos-iso/flake.nix`
- `appendix/ventoy-usb/nixos-iso/flake.lock`
- `appendix/ventoy-usb/nixos-iso/configuration.nix` (after M1 cherry-pick complete)
- `appendix/ventoy-usb/archiso/` (entire directory)
- `appendix/ventoy-usb/nixos-iso/root-dotfiles/` (after M1 cherry-pick complete)
- `appendix/ventoy-usb/build-iso.sh`
- `appendix/ventoy-usb/create-ventoy-usb.sh`
- `appendix/ventoy-usb/update-usb.sh`
- `appendix/ventoy-usb/ventoy.json`

Cherry-picked from `appendix/ventoy-usb/toolbox/` before deletion:
- `format-drive.sh` → split across `hosts/mandragora-usb/install/{detect,format,render-config,install}.sh`
- `hw-diag.sh` → kept as `hosts/mandragora-usb/diagnostics/hw-diag.sh` (added to PATH on the live system; useful for recovery)
- `gpu-stress.sh` → kept as `hosts/mandragora-usb/diagnostics/gpu-stress.sh` (same rationale)

After cherry-picks complete, `appendix/ventoy-usb/toolbox/` is deleted.

Runtime state (refiner, not in repo):
- `/home/m/Projects/mandragora-usb-refiner/state/{usb.img.work,target.qcow2,OVMF_VARS.fd,run-*.log}`
