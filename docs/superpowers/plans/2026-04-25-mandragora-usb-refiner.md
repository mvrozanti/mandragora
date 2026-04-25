# Mandragora USB + Refiner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote the live USB to a first-class NixOS host (`mandragora-usb`), replace Ventoy with a single raw-efi disk image built by `nixos-generators`, and add a flake-app refiner that boots the image in QEMU with a blank target disk so the install pipeline can be exercised iteratively without flashing real hardware.

**Architecture:** Three coupled changes in the main flake at `/etc/nixos/mandragora`. (1) `hosts/mandragora-usb/` declares a console-only Tier 2 NixOS configuration. (2) `packages.x86_64-linux.usbImage` produces a USB-bootable raw-efi image via `nixos-generators`. (3) `apps.x86_64-linux.refiner` is a `writeShellApplication`-wrapped QEMU harness with state-dir at `/home/m/Projects/mandragora-usb-refiner/state/`. Shared modules gain a `mandragora.profile = "desktop" | "live"` enum so desktop and USB hosts share code without duplication.

**Tech Stack:** Nix flakes (nixpkgs-unstable) · `nixos-generators` (`format = "raw-efi"`) · QEMU + KVM + OVMF · sops-nix + age (with passphrase) · systemd · bash + bats for install scripts · expect for `--auto` driver

**Spec:** [`/etc/nixos/mandragora/docs/superpowers/specs/2026-04-25-mandragora-usb-refiner-design.md`](../specs/2026-04-25-mandragora-usb-refiner-design.md)

---

## Pre-flight

Before starting any task: this work modifies your daily-driver desktop config. Discipline:

- Every task that touches a shared module must `nixos-rebuild build --flake .#mandragora-desktop` (no `switch`) before commit. Never push a broken desktop.
- USB image build must also succeed before any commit that touches `hosts/mandragora-usb/` or shared modules.
- Real-hardware USB test (M1 final task) requires a 16 GB USB stick and one machine you can reboot.

If a desktop or USB build fails: fix or revert before commit. Don't accumulate broken state.

## File Structure

Created in this plan:

```
hosts/mandragora-usb/
├── default.nix                      Live host config (live profile)
├── install/
│   ├── lib.sh                       Logging, root check, prompts
│   ├── detect.sh                    Boot-media + target enumeration
│   ├── format.sh                    sgdisk + mkfs + mount
│   ├── render-config.sh             Hardware config + host template
│   └── install.sh                   Orchestrator (with git-pull)
├── diagnostics/
│   ├── hw-diag.sh                   (cherry-picked from old toolbox)
│   └── gpu-stress.sh                (cherry-picked from old toolbox)
└── tests/
    └── install/
        ├── test_detect.bats         Unit tests for detect.sh logic
        ├── test_format.bats         Unit tests for format.sh logic
        └── test_render_config.bats  Unit tests for render-config.sh

modules/shared/                       NEW directory for cross-profile modules
├── zsh.nix                          (added in M4)
└── nvim.nix                         (added in M4)

refiner/
├── default.nix                      Flake-app wrapper
├── lib.sh                           State-dir, KVM check, OVMF copy
├── run-vm.sh                        QEMU invocation (manual mode)
└── auto-install.sh                  Scripted install + verify (--auto)

secrets/
└── usb-key.age                      age -p-encrypted USB-host key

docs/superpowers/specs/2026-04-25-mandragora-usb-refiner-design.md
docs/superpowers/plans/2026-04-25-mandragora-usb-refiner.md  ← this file
```

Modified:

```
flake.nix                            Add nixos-generators input, host, package, app
.sops.yaml                           Add USB recipient
modules/desktop/hyprland.nix         Make desktop-only via profile
modules/desktop/waybar.nix           Make desktop-only via profile
modules/user/home.nix                Gate desktop-flavor pieces
modules/core/impermanence.nix        Make desktop-only
hosts/mandragora-desktop/default.nix Set mandragora.profile = "desktop"
```

Deleted (last):

```
appendix/ventoy-usb/                 (entire tree, after cherry-picks)
```

---

## M1 — Minimal USB host

Smallest possible host that builds, boots in QEMU, and boots on a real USB. No shared modules yet (inline config). Hard exit gate on real-hardware boot.

### Task M1.1: Add `nixos-generators` flake input

**Files:**
- Modify: `flake.nix`

- [ ] **Step 1: Read current flake.nix to plan the change**

Run: `cat /etc/nixos/mandragora/flake.nix`

Expected: see existing inputs (nixpkgs, home-manager, sops-nix, impermanence) and a single nixosConfigurations entry for `mandragora-desktop`.

- [ ] **Step 2: Add the input**

Edit `/etc/nixos/mandragora/flake.nix`. In the `inputs = { ... }` block, add after `impermanence`:

```nix
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

In the outputs signature, add `nixos-generators` to the destructured args:

```nix
  outputs = { self, nixpkgs, home-manager, sops-nix, impermanence, nixos-generators, ... }@inputs:
```

- [ ] **Step 3: Verify the flake still evaluates**

Run: `nix flake check /etc/nixos/mandragora --no-build 2>&1 | tail -20`

Expected: no evaluation errors. Existing `mandragora-desktop` still listed.

- [ ] **Step 4: Commit**

```bash
cd /etc/nixos/mandragora
git add flake.nix flake.lock
git commit -F - <<'EOF'
flake: add nixos-generators input

For building the mandragora-usb raw-efi disk image.
EOF
```

### Task M1.2: Create skeleton `hosts/mandragora-usb/default.nix`

**Files:**
- Create: `hosts/mandragora-usb/default.nix`

- [ ] **Step 1: Create the host directory and skeleton config**

```bash
mkdir -p /etc/nixos/mandragora/hosts/mandragora-usb
```

Write `/etc/nixos/mandragora/hosts/mandragora-usb/default.nix`:

```nix
{ config, pkgs, lib, ... }:

{
  networking.hostName = "mandragora-usb";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  nixpkgs.config.allowUnfree = true;

  time.timeZone = "America/Sao_Paulo";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  users.users.m = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    shell = pkgs.zsh;
    initialPassword = "mandragora";
  };

  users.users.root.initialPassword = "mandragora";

  programs.zsh.enable = true;
  programs.tmux.enable = true;
  programs.nix-ld.enable = true;

  environment.systemPackages = with pkgs; [
    git
    neovim
    sops
    age
    openssh
    networkmanager
    htop
    curl
    wget
    pciutils
    usbutils
    parted
    gptfdisk
    dosfstools
    e2fsprogs
    util-linux
  ];

  networking.networkmanager.enable = true;
  networking.wireless.enable = false;

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    settings.PasswordAuthentication = true;
  };

  hardware.enableRedistributableFirmware = true;

  system.stateVersion = "25.05";
}
```

- [ ] **Step 2: Verify it parses**

Run: `nix-instantiate --parse /etc/nixos/mandragora/hosts/mandragora-usb/default.nix > /dev/null && echo OK`

Expected: `OK`

- [ ] **Step 3: Commit**

```bash
cd /etc/nixos/mandragora
git add hosts/mandragora-usb/default.nix
git commit -F - <<'EOF'
hosts/mandragora-usb: add minimal skeleton

Console-only host with zsh, tmux, nvim, and basic install tooling. Will
be wired into the flake and built as a raw-efi image in subsequent tasks.
EOF
```

### Task M1.3: Wire `mandragora-usb` into `flake.nix nixosConfigurations`

**Files:**
- Modify: `flake.nix`

- [ ] **Step 1: Add the nixosConfigurations entry**

Edit `/etc/nixos/mandragora/flake.nix`. Inside the `nixosConfigurations = { ... }` block, after `mandragora-desktop`:

```nix
        mandragora-usb = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/mandragora-usb/default.nix
            "${nixpkgs}/nixos/modules/profiles/installation-device.nix"
            sops-nix.nixosModules.sops
          ];
        };
```

- [ ] **Step 2: Verify both hosts evaluate**

Run: `nix flake show /etc/nixos/mandragora 2>&1 | head -20`

Expected: see `mandragora-desktop` and `mandragora-usb` listed under `nixosConfigurations`.

- [ ] **Step 3: Build the toplevel (no boot, just evaluate the closure)**

Run: `nix build /etc/nixos/mandragora#nixosConfigurations.mandragora-usb.config.system.build.toplevel --no-link 2>&1 | tail -10`

Expected: build succeeds. May take 5-10 min the first time as the closure populates.

- [ ] **Step 4: Commit**

```bash
cd /etc/nixos/mandragora
git add flake.nix
git commit -F - <<'EOF'
flake: wire mandragora-usb into nixosConfigurations

Imports installation-device.nix profile so the live system has the
expected installer machinery (autologin, no display manager, etc).
EOF
```

### Task M1.4: Add `packages.x86_64-linux.usbImage` via `nixos-generators`

**Files:**
- Modify: `flake.nix`

- [ ] **Step 1: Add the packages output**

Edit `/etc/nixos/mandragora/flake.nix`. After the `nixosConfigurations` block, add:

```nix
      packages.${system}.usbImage = nixos-generators.nixosGenerate {
        inherit system;
        format = "raw-efi";
        modules = [
          ./hosts/mandragora-usb/default.nix
          sops-nix.nixosModules.sops
        ];
      };
```

Note: `installation-device.nix` is intentionally **not** included in the image build — its tweaks (e.g. autologin to console as `nixos`) clash with our user `m`. The host config's own package set drives the image contents.

- [ ] **Step 2: Build the image**

Run: `nix build /etc/nixos/mandragora#usbImage 2>&1 | tail -20`

Expected: build succeeds; result symlink points at a directory containing `nixos.img` (or similar; `nixos-generators`'s raw-efi format names vary by version).

- [ ] **Step 3: Locate and inspect the image**

Run: `ls -lh /etc/nixos/mandragora/result/ && file /etc/nixos/mandragora/result/*.img`

Expected: a raw disk image, ~3-6 GB. `file` reports "DOS/MBR boot sector" or "GPT partition table".

- [ ] **Step 4: Commit**

```bash
cd /etc/nixos/mandragora
git add flake.nix
git commit -F - <<'EOF'
flake: add packages.usbImage via nixos-generators raw-efi

Single Nix derivation produces the USB-bootable disk image. Builds
incrementally; consumed by both real-USB flash and the refiner.
EOF
```

### Task M1.5: Smoke-boot the image in QEMU manually

**Files:** none (verification only)

- [ ] **Step 1: Locate the image**

Run: `IMG=$(readlink -f /etc/nixos/mandragora/result/*.img) && echo "$IMG" && ls -lh "$IMG"`

Expected: absolute path to the raw image; size 3-6 GB.

- [ ] **Step 2: Make a writable copy (the Nix-store original is read-only)**

Run:

```bash
mkdir -p /tmp/m1-smoke
cp --reflink=auto "$IMG" /tmp/m1-smoke/usb.img
chmod u+w /tmp/m1-smoke/usb.img
cp /run/current-system/sw/share/qemu/edk2-x86_64-code.fd /tmp/m1-smoke/OVMF_CODE.fd 2>/dev/null \
  || cp $(nix eval --raw nixpkgs#OVMF.fd.fd)/FV/OVMF_CODE.fd /tmp/m1-smoke/OVMF_CODE.fd
cp $(nix eval --raw nixpkgs#OVMF.fd.fd)/FV/OVMF_VARS.fd /tmp/m1-smoke/OVMF_VARS.fd
chmod u+w /tmp/m1-smoke/OVMF_VARS.fd
```

Expected: three files in `/tmp/m1-smoke/`.

- [ ] **Step 3: Boot in QEMU**

Run:

```bash
qemu-system-x86_64 \
  -enable-kvm -m 4096 -smp 2 \
  -drive if=pflash,format=raw,readonly=on,file=/tmp/m1-smoke/OVMF_CODE.fd \
  -drive if=pflash,format=raw,file=/tmp/m1-smoke/OVMF_VARS.fd \
  -drive file=/tmp/m1-smoke/usb.img,if=virtio,format=raw \
  -netdev user,id=net0 -device virtio-net,netdev=net0 \
  -display none -serial stdio
```

Expected: kernel boots, systemd starts, login prompt appears within 60 s. Login as `m` with password `mandragora`. `zsh` should be the shell. `nvim --version`, `tmux -V`, `nmtui --version` all succeed.

To exit: `poweroff` from inside the VM, or Ctrl+A X to kill QEMU.

- [ ] **Step 4: Document the smoke result**

This step is purely confirmatory. If the boot fails, debug the host config or `installation-device.nix` import; do not proceed to M1.6 until this passes.

### Task M1.6: Add `/persist` partition mount stub

**Files:**
- Modify: `hosts/mandragora-usb/default.nix`

- [ ] **Step 1: Add a fileSystems entry for `/persist`**

The raw-efi format produces an image with one ESP and one root partition. We don't yet have a `/persist` partition; it will be added at flash time as the third partition of the USB. For now, gracefully stub: try to mount, fail soft (boot continues with tmpfs).

Edit `/etc/nixos/mandragora/hosts/mandragora-usb/default.nix`. Add inside the top-level config block:

```nix
  fileSystems."/persist" = {
    device = "/dev/disk/by-label/mandragora-persist";
    fsType = "ext4";
    options = [ "nofail" "x-systemd.device-timeout=10" ];
  };

  systemd.tmpfiles.rules = [
    "d /persist 0755 root root - -"
    "d /persist/npm-global 0755 m users - -"
  ];
```

- [ ] **Step 2: Rebuild the image**

Run: `nix build /etc/nixos/mandragora#usbImage --rebuild 2>&1 | tail -10`

Expected: build succeeds. (`--rebuild` forces a re-derivation if Nix thought it was cached.)

- [ ] **Step 3: Verify in QEMU that boot still succeeds without `/persist`**

Repeat M1.5 step 3 with the new image. Expected: boot succeeds; `systemctl status persist.mount` shows "deactivated" (graceful — `nofail` did its job). `/persist` may or may not exist as a directory depending on tmpfiles ordering; that's OK for now.

- [ ] **Step 4: Commit**

```bash
cd /etc/nixos/mandragora
git add hosts/mandragora-usb/default.nix
git commit -F - <<'EOF'
hosts/mandragora-usb: stub /persist mount

Soft-fails when the partition is absent (the raw-efi image only contains
ESP + root). The /persist partition is created at flash time and will
hold npm-global and other long-lived state.
EOF
```

### Task M1.7: Flash to a real 16 GB USB and boot one machine

**Files:** none (real-hardware verification)

This is M1's hard exit gate. Per the spec's suspicious-assumptions section, "QEMU works" is not proof of real-USB-bootable.

- [ ] **Step 1: Identify the USB device**

Insert a 16 GB USB stick. Run: `lsblk -o NAME,SIZE,MODEL,RM`. Identify the device (expect `RM=1`, size ~16 GB). Substitute the right path below for `/dev/sdX`.

**WARNING:** the next step destroys all data on `/dev/sdX`. Triple-check the device path.

- [ ] **Step 2: Flash**

Run:

```bash
sudo dd if=/etc/nixos/mandragora/result/*.img of=/dev/sdX bs=4M status=progress oflag=direct conv=fsync
sudo sync
```

Expected: write completes; `dd` reports the number of MB written matching the image size.

- [ ] **Step 3: Inspect the partition table**

Run: `sudo parted /dev/sdX print`

Expected: GPT partition table with at least: `boot, esp` (FAT32, ~512 MB) and a root partition (ext4 or similar). Size totals less than 16 GB; remaining space is unallocated (we'll use it for `/persist` in M1.8).

- [ ] **Step 4: Boot a real machine from the USB**

Pick a machine you can reboot. Plug the USB in. Boot from it (firmware-specific, often F12/F8/Esc at POST). Watch the boot.

Expected: kernel boots, login prompt appears, `m` / `mandragora` works, `nvim`/`tmux`/`nmtui` available. The boot device shows up in `mount` as `/dev/sdaN` (or similar) under `/`.

If boot fails: debug. Common causes are partition flags (the ESP needs the `boot,esp` flags, which `nixos-generators -f raw-efi` should set), missing UEFI bootloader entry, or Secure Boot enabled on the test machine. **Do not proceed to M2 until this passes.**

- [ ] **Step 5: Document the result**

No commit; this is a manual verification gate. Record the test machine's hardware (CPU, GPU, manufacturer) in your notes — useful when M8's portability scenarios surface later.

### Task M1.8: Add a `/persist` partition to the flashed USB

**Files:** none (manual partition creation; will be automated in a flash script later)

- [ ] **Step 1: Identify the unallocated space**

Run: `sudo parted /dev/sdX print free`

Expected: see "Free Space" of several GB at the end of the device (after the root partition).

- [ ] **Step 2: Create a third partition for `/persist`**

Run:

```bash
START=$(sudo parted /dev/sdX -m print free | awk -F: '/free/ && $1 != "1" {print $2; exit}')
sudo parted /dev/sdX --script mkpart mandragora-persist ext4 "$START" 100%
sudo partprobe /dev/sdX
sudo mkfs.ext4 -L mandragora-persist /dev/sdX3
```

(If the new partition is `/dev/sdX4` due to numbering quirks, adjust accordingly.)

- [ ] **Step 3: Re-boot from the USB and verify `/persist` mounts**

Reboot the test machine from the USB. After login, run: `mountpoint /persist && df -h /persist`

Expected: `/persist is a mountpoint` and shows the new partition with several GB free.

- [ ] **Step 4: Document procedure for the flash script**

This manual procedure becomes part of an automated `flash-usb.sh` later (out of scope for MVP). For now, note in your worktree:

```bash
echo "Manual /persist creation steps documented in M1.8 of plan." > /tmp/m1-flash-notes.md
```

This is not committed.

---

## M2 — Refiner harness

A flake app that boots the M1 image in QEMU with KVM, an attached blank target disk, and serial-only output. State (target.qcow2, OVMF NVRAM) lives at `/home/m/Projects/mandragora-usb-refiner/state/`.

### Task M2.1: Create `refiner/lib.sh`

**Files:**
- Create: `refiner/lib.sh`

- [ ] **Step 1: Create the refiner directory**

```bash
mkdir -p /etc/nixos/mandragora/refiner
```

- [ ] **Step 2: Write `lib.sh`**

`/etc/nixos/mandragora/refiner/lib.sh`:

```bash
#!/usr/bin/env bash
# Shared helpers for refiner scripts. Sourced, not executed.

set -euo pipefail

REFINER_STATE_DIR="${REFINER_STATE_DIR:-/home/m/Projects/mandragora-usb-refiner/state}"
REFINER_TARGET_SIZE="${REFINER_TARGET_SIZE:-40G}"
REFINER_RAM="${REFINER_RAM:-6144}"
REFINER_VCPUS="${REFINER_VCPUS:-4}"

log()  { printf '[refiner] %s\n' "$*"; }
die()  { printf '[refiner] FATAL: %s\n' "$*" >&2; exit 1; }

ensure_state_dir() {
    mkdir -p "$REFINER_STATE_DIR"
}

check_kvm() {
    [[ -r /dev/kvm && -w /dev/kvm ]] \
        || die "/dev/kvm not accessible. Add your user to the 'kvm' group: sudo usermod -aG kvm \$USER && relogin."
}

check_ram() {
    local free_mb
    free_mb=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
    if (( free_mb < 12000 )); then
        log "WARNING: less than 12 GB RAM available (${free_mb} MB). VM may be tight."
    fi
}

allocate_run_log() {
    local ts
    ts=$(date +%Y%m%d-%H%M%S)
    REFINER_RUN_LOG="${REFINER_STATE_DIR}/run-${ts}-$$.log"
    log "Run log: $REFINER_RUN_LOG"
}

prepare_ovmf_vars() {
    local src_vars="${1:?prepare_ovmf_vars: pass OVMF_VARS source path}"
    local dst="${REFINER_STATE_DIR}/OVMF_VARS.fd"
    rm -f "$dst"
    cp "$src_vars" "$dst"
    chmod u+w "$dst"
    REFINER_OVMF_VARS="$dst"
}

prepare_target_disk() {
    local dst="${REFINER_STATE_DIR}/target.qcow2"
    rm -f "$dst"
    qemu-img create -f qcow2 "$dst" "$REFINER_TARGET_SIZE" >/dev/null
    REFINER_TARGET="$dst"
}
```

Make it executable for shellcheck convenience:

```bash
chmod +x /etc/nixos/mandragora/refiner/lib.sh
```

- [ ] **Step 3: Lint with shellcheck**

Run: `shellcheck /etc/nixos/mandragora/refiner/lib.sh`

Expected: no errors. (Warnings about unused variables in `lib.sh` may appear; ignore them since the file is sourced.)

- [ ] **Step 4: Commit**

```bash
cd /etc/nixos/mandragora
git add refiner/lib.sh
git commit -F - <<'EOF'
refiner: add lib.sh with state-dir helpers

KVM check, RAM warning, OVMF NVRAM copy, target disk allocation, run-log
naming. Sourced by run-vm.sh and auto-install.sh.
EOF
```

### Task M2.2: Create `refiner/run-vm.sh`

**Files:**
- Create: `refiner/run-vm.sh`

- [ ] **Step 1: Write `run-vm.sh`**

`/etc/nixos/mandragora/refiner/run-vm.sh`:

```bash
#!/usr/bin/env bash
# Boot the mandragora-usb image in QEMU with a blank target disk.
# Usage: run-vm.sh [--ram MB] [--vcpus N]

set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "$(readlink -f "$0")")/lib.sh"

USB_IMG="${MANDRAGORA_USB_IMG:?MANDRAGORA_USB_IMG must point to a raw USB image}"
OVMF_CODE="${MANDRAGORA_OVMF_CODE:?MANDRAGORA_OVMF_CODE must point to OVMF_CODE.fd}"
OVMF_VARS_SRC="${MANDRAGORA_OVMF_VARS:?MANDRAGORA_OVMF_VARS must point to OVMF_VARS.fd template}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ram) REFINER_RAM="$2"; shift 2 ;;
        --vcpus) REFINER_VCPUS="$2"; shift 2 ;;
        --) shift; break ;;
        *) die "unknown arg: $1" ;;
    esac
done

check_kvm
check_ram
ensure_state_dir
allocate_run_log
prepare_ovmf_vars "$OVMF_VARS_SRC"
prepare_target_disk

log "Booting mandragora-usb image: $USB_IMG"
log "Target disk: $REFINER_TARGET ($REFINER_TARGET_SIZE)"
log "Press Ctrl+A then X to terminate QEMU."
log "---"

exec qemu-system-x86_64 \
    -enable-kvm \
    -m "$REFINER_RAM" \
    -smp "$REFINER_VCPUS" \
    -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}" \
    -drive "if=pflash,format=raw,file=${REFINER_OVMF_VARS}" \
    -drive "file=${USB_IMG},if=virtio,format=raw,snapshot=on" \
    -drive "file=${REFINER_TARGET},if=virtio,format=qcow2" \
    -netdev user,id=net0 \
    -device virtio-net,netdev=net0 \
    -device virtio-rng-pci \
    -display none \
    -serial mon:stdio \
    2>&1 | tee "$REFINER_RUN_LOG"
```

```bash
chmod +x /etc/nixos/mandragora/refiner/run-vm.sh
```

- [ ] **Step 2: Lint with shellcheck**

Run: `shellcheck /etc/nixos/mandragora/refiner/run-vm.sh`

Expected: no errors.

- [ ] **Step 3: Smoke-run manually with explicit env vars**

Run:

```bash
export MANDRAGORA_USB_IMG=$(readlink -f /etc/nixos/mandragora/result/*.img)
export MANDRAGORA_OVMF_CODE=$(nix eval --raw nixpkgs#OVMF.fd.fd)/FV/OVMF_CODE.fd
export MANDRAGORA_OVMF_VARS=$(nix eval --raw nixpkgs#OVMF.fd.fd)/FV/OVMF_VARS.fd
/etc/nixos/mandragora/refiner/run-vm.sh
```

Expected: the VM boots; login prompt appears; you can log in as `m`. Inside the VM, `lsblk` shows `vda` (USB image, several GB) and `vdb` (target disk, ~40 GB, blank).

To exit: `poweroff` inside the VM, or Ctrl+A X at the host terminal.

- [ ] **Step 4: Commit**

```bash
cd /etc/nixos/mandragora
git add refiner/run-vm.sh
git commit -F - <<'EOF'
refiner: add run-vm.sh

Boots the USB image with snapshot=on (no persistent overlay), recreated
target.qcow2, recreated OVMF NVRAM. Pure serial; no GUI. State at
/home/m/Projects/mandragora-usb-refiner/state/.
EOF
```

### Task M2.3: Wrap the refiner as a flake app

**Files:**
- Create: `refiner/default.nix`
- Modify: `flake.nix`

- [ ] **Step 1: Write `refiner/default.nix`**

`/etc/nixos/mandragora/refiner/default.nix`:

```nix
{ pkgs, usbImage }:

let
  ovmf = pkgs.OVMF.fd;
in
pkgs.writeShellApplication {
  name = "refiner";
  runtimeInputs = with pkgs; [
    qemu_kvm
    coreutils
    util-linux
    e2fsprogs
    dosfstools
    gawk
  ];
  text = ''
    export MANDRAGORA_USB_IMG="${usbImage}/nixos.img"
    export MANDRAGORA_OVMF_CODE="${ovmf}/FV/OVMF_CODE.fd"
    export MANDRAGORA_OVMF_VARS="${ovmf}/FV/OVMF_VARS.fd"
    exec ${./run-vm.sh} "$@"
  '';
}
```

Note: `${usbImage}/nixos.img` may need adjustment depending on `nixos-generators`'s actual output filename. Check with `ls $(nix eval --raw .#usbImage)/`.

- [ ] **Step 2: Verify the image's actual file path**

Run: `ls $(nix eval --raw /etc/nixos/mandragora#usbImage)/`

Expected: a single `.img` file or similar. Note the exact name. If it's not `nixos.img`, fix `refiner/default.nix` to point at the correct file.

- [ ] **Step 3: Wire the app into `flake.nix`**

Edit `/etc/nixos/mandragora/flake.nix`. After the `packages.${system}.usbImage` declaration, add:

```nix
      apps.${system}.refiner = {
        type = "app";
        program = "${(import ./refiner/default.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          usbImage = self.packages.${system}.usbImage;
        })}/bin/refiner";
      };
```

- [ ] **Step 4: Run the app**

Run: `nix run /etc/nixos/mandragora#refiner 2>&1 | head -30`

Expected: the refiner kicks off, KVM check passes, run-log path printed, VM boots. (If you can't see serial output without redirection, run without piping: `nix run /etc/nixos/mandragora#refiner`.)

If the image filename doesn't match what's in `refiner/default.nix`, the run will die with "MANDRAGORA_USB_IMG must point to a raw USB image" or similar. Fix and retry.

- [ ] **Step 5: Commit**

```bash
cd /etc/nixos/mandragora
git add refiner/default.nix flake.nix
git commit -F - <<'EOF'
refiner: wrap as flake app

`nix run .#refiner` is now the entry point. Resolves USB image path and
OVMF firmware via Nix; user sees a boring command that just works.
EOF
```

---

## M3 — Install pipeline minimal

The install scripts as `pkgs.writeShellApplication` derivations. Tested first with bats unit tests for non-destructive logic, then end-to-end in the refiner.

### Task M3.1: Set up bats test infrastructure

**Files:**
- Create: `hosts/mandragora-usb/tests/install/test_lib.bats`

- [ ] **Step 1: Create the tests directory**

```bash
mkdir -p /etc/nixos/mandragora/hosts/mandragora-usb/tests/install
```

- [ ] **Step 2: Write a stub test to verify bats works**

`/etc/nixos/mandragora/hosts/mandragora-usb/tests/install/test_lib.bats`:

```bash
#!/usr/bin/env bats

@test "bats is callable" {
    run echo hello
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}
```

- [ ] **Step 3: Run bats**

Run: `nix shell nixpkgs#bats -c bats /etc/nixos/mandragora/hosts/mandragora-usb/tests/install/test_lib.bats`

Expected: 1 test passed.

- [ ] **Step 4: Commit**

```bash
cd /etc/nixos/mandragora
git add hosts/mandragora-usb/tests/install/test_lib.bats
git commit -F - <<'EOF'
tests/install: bootstrap bats with stub test

Will hold unit tests for the install pipeline's non-destructive logic
(disk enumeration, microcode detection, GPU detection, etc).
EOF
```

### Task M3.2: Write `install/lib.sh` with logging + confirmation helpers (test-first)

**Files:**
- Create: `hosts/mandragora-usb/install/lib.sh`
- Modify: `hosts/mandragora-usb/tests/install/test_lib.bats`

- [ ] **Step 1: Write failing tests for lib.sh helpers**

Replace `test_lib.bats` content with:

```bash
#!/usr/bin/env bats

setup() {
    LIB="$BATS_TEST_DIRNAME/../../install/lib.sh"
    # shellcheck disable=SC1090
    source "$LIB"
}

@test "log_info prints to stderr with prefix" {
    run bash -c 'source "'"$LIB"'"; log_info "hello" 2>&1 1>/dev/null'
    [ "$status" -eq 0 ]
    [[ "$output" =~ \[info\].*hello ]]
}

@test "log_error prints to stderr with prefix" {
    run bash -c 'source "'"$LIB"'"; log_error "bad" 2>&1 1>/dev/null'
    [ "$status" -eq 0 ]
    [[ "$output" =~ \[error\].*bad ]]
}

@test "die exits non-zero with message" {
    run bash -c 'source "'"$LIB"'"; die "broken"'
    [ "$status" -ne 0 ]
    [[ "$output" =~ broken ]]
}

@test "require_root fails when not root" {
    run bash -c 'source "'"$LIB"'"; (export EUID=1000; require_root)'
    [ "$status" -ne 0 ]
    [[ "$output" =~ root ]]
}

@test "confirm_typed accepts the expected token" {
    run bash -c 'source "'"$LIB"'"; echo "YES" | confirm_typed YES "are you sure"'
    [ "$status" -eq 0 ]
}

@test "confirm_typed rejects wrong input" {
    run bash -c 'source "'"$LIB"'"; echo "no" | confirm_typed YES "are you sure"'
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run tests to verify they fail (file not yet present)**

Run: `nix shell nixpkgs#bats -c bats /etc/nixos/mandragora/hosts/mandragora-usb/tests/install/test_lib.bats`

Expected: all 6 tests fail with "No such file or directory" sourcing `lib.sh`.

- [ ] **Step 3: Implement `install/lib.sh`**

`/etc/nixos/mandragora/hosts/mandragora-usb/install/lib.sh`:

```bash
#!/usr/bin/env bash
# Shared helpers for the install pipeline. Sourced, not executed.

log_info()  { printf '[info] %s\n' "$*" >&2; }
log_warn()  { printf '[warn] %s\n' "$*" >&2; }
log_error() { printf '[error] %s\n' "$*" >&2; }
die()       { log_error "$*"; exit 1; }

require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        die "this command must run as root"
    fi
}

# Read a token from stdin and exit non-zero if it doesn't match the expected literal.
# Usage: confirm_typed EXPECTED "prompt text"
confirm_typed() {
    local expected="$1"
    local prompt="$2"
    local got
    log_info "$prompt"
    log_info "Type ${expected} to continue:"
    read -r got
    [[ "$got" == "$expected" ]] || { log_error "got '$got', expected '$expected' — aborting."; return 1; }
}
```

```bash
mkdir -p /etc/nixos/mandragora/hosts/mandragora-usb/install
chmod +x /etc/nixos/mandragora/hosts/mandragora-usb/install/lib.sh
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `nix shell nixpkgs#bats -c bats /etc/nixos/mandragora/hosts/mandragora-usb/tests/install/test_lib.bats`

Expected: 6 tests passed.

- [ ] **Step 5: Lint**

Run: `shellcheck /etc/nixos/mandragora/hosts/mandragora-usb/install/lib.sh`

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
cd /etc/nixos/mandragora
git add hosts/mandragora-usb/install/lib.sh hosts/mandragora-usb/tests/install/test_lib.bats
git commit -F - <<'EOF'
install: add lib.sh with log/die/require_root/confirm_typed

Test-driven; 6 unit tests via bats. confirm_typed enforces typed-token
confirmation (e.g. "WIPE", "YES") for destructive ops.
EOF
```

### Task M3.3: Write `install/detect.sh` with boot-media + target enumeration (test-first)

**Files:**
- Create: `hosts/mandragora-usb/install/detect.sh`
- Create: `hosts/mandragora-usb/tests/install/test_detect.bats`

- [ ] **Step 1: Write failing tests**

`/etc/nixos/mandragora/hosts/mandragora-usb/tests/install/test_detect.bats`:

```bash
#!/usr/bin/env bats

setup() {
    DETECT="$BATS_TEST_DIRNAME/../../install/detect.sh"
}

@test "detect.sh is executable" {
    [ -x "$DETECT" ]
}

@test "_resolve_boot_disk returns the disk holding /" {
    # Source the script; call its internal helper.
    run bash -c 'source "'"$DETECT"'" --source-only; _resolve_boot_disk'
    [ "$status" -eq 0 ]
    # Output should be a /dev path
    [[ "$output" =~ ^/dev/ ]]
}

@test "_list_block_disks excludes loop, ram, partitions" {
    run bash -c 'source "'"$DETECT"'" --source-only; _list_block_disks'
    [ "$status" -eq 0 ]
    # No partitions in output
    refute_partitions=$(echo "$output" | grep -E '/dev/.*[0-9]+$' || true)
    [ -z "$refute_partitions" ]
}

@test "_filter_targets excludes the boot disk" {
    # Mock the boot disk by overriding the helper
    run bash -c '
        source "'"$DETECT"'" --source-only
        _resolve_boot_disk() { echo /dev/sda; }
        echo -e "/dev/sda\n/dev/sdb\n/dev/nvme0n1" | _filter_targets
    '
    [ "$status" -eq 0 ]
    # /dev/sda should be filtered out
    [[ ! "$output" =~ /dev/sda$ ]]
    [[ "$output" =~ /dev/sdb ]]
    [[ "$output" =~ /dev/nvme0n1 ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `nix shell nixpkgs#bats -c bats /etc/nixos/mandragora/hosts/mandragora-usb/tests/install/test_detect.bats`

Expected: 4 tests fail (file not present, helpers undefined).

- [ ] **Step 3: Implement `install/detect.sh`**

`/etc/nixos/mandragora/hosts/mandragora-usb/install/detect.sh`:

```bash
#!/usr/bin/env bash
# Identify boot media and enumerate candidate target disks.
# Refuses if no candidate is available.
# Usage: detect.sh
# Sourceable: detect.sh --source-only

set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "$(readlink -f "$0")")/lib.sh"

# Resolve the disk whose partition holds / (the live system root).
_resolve_boot_disk() {
    local root_dev
    root_dev=$(findmnt -no SOURCE / | sed 's/\[.*\]//')   # strip btrfs subvol notation
    # Convert /dev/sda1 → /dev/sda, /dev/nvme0n1p2 → /dev/nvme0n1
    lsblk -no PKNAME "$root_dev" 2>/dev/null | head -n1 | awk '{print "/dev/" $1}'
}

# Enumerate full block devices (not partitions, not loop, not ram).
_list_block_disks() {
    lsblk -dno NAME,TYPE | awk '$2 == "disk" {print "/dev/" $1}'
}

# Filter out the boot disk from a list of disks on stdin.
_filter_targets() {
    local boot
    boot=$(_resolve_boot_disk)
    grep -v "^${boot}$" || true
}

main() {
    local boot
    boot=$(_resolve_boot_disk)
    log_info "Boot disk: $boot"

    local candidates
    candidates=$(_list_block_disks | _filter_targets)
    if [[ -z "$candidates" ]]; then
        die "No target disk available. The only disk is the boot media ($boot)."
    fi

    log_info "Candidate target disks:"
    while IFS= read -r dev; do
        local size model
        size=$(lsblk -dno SIZE "$dev")
        model=$(lsblk -dno MODEL "$dev" || echo "?")
        printf '  %s  %s  %s\n' "$dev" "$size" "$model" >&2
    done <<< "$candidates"

    # Print just the candidate devices to stdout for the orchestrator.
    echo "$candidates"
}

# Allow sourcing for tests
if [[ "${1:-}" != "--source-only" ]]; then
    main "$@"
fi
```

```bash
chmod +x /etc/nixos/mandragora/hosts/mandragora-usb/install/detect.sh
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `nix shell nixpkgs#bats -c bats /etc/nixos/mandragora/hosts/mandragora-usb/tests/install/test_detect.bats`

Expected: 4 tests pass.

- [ ] **Step 5: Lint**

Run: `shellcheck /etc/nixos/mandragora/hosts/mandragora-usb/install/detect.sh`

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
cd /etc/nixos/mandragora
git add hosts/mandragora-usb/install/detect.sh hosts/mandragora-usb/tests/install/test_detect.bats
git commit -F - <<'EOF'
install: add detect.sh with boot-media filtering

Identifies the disk hosting / (the running USB) and lists the rest as
candidate targets. Refuses to proceed if the only disk is the boot media.
EOF
```

### Task M3.4: Write `install/format.sh` with sgdisk + mkfs (test-first for non-destructive logic)

**Files:**
- Create: `hosts/mandragora-usb/install/format.sh`
- Create: `hosts/mandragora-usb/tests/install/test_format.bats`

- [ ] **Step 1: Write failing tests for the size-check logic only (the destructive parts test in the refiner)**

`/etc/nixos/mandragora/hosts/mandragora-usb/tests/install/test_format.bats`:

```bash
#!/usr/bin/env bats

setup() {
    FMT="$BATS_TEST_DIRNAME/../../install/format.sh"
}

@test "format.sh is executable" {
    [ -x "$FMT" ]
}

@test "_check_size accepts >=30 GB" {
    run bash -c 'source "'"$FMT"'" --source-only; _check_size 64424509440'   # 60 GB
    [ "$status" -eq 0 ]
}

@test "_check_size warns at 30-60 GB" {
    run bash -c 'source "'"$FMT"'" --source-only; _check_size 42949672960 2>&1'   # 40 GB
    [ "$status" -eq 0 ]
    [[ "$output" =~ small ]]
}

@test "_check_size refuses <30 GB" {
    run bash -c 'source "'"$FMT"'" --source-only; _check_size 10737418240'   # 10 GB
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `nix shell nixpkgs#bats -c bats /etc/nixos/mandragora/hosts/mandragora-usb/tests/install/test_format.bats`

Expected: 4 tests fail.

- [ ] **Step 3: Implement `install/format.sh`**

`/etc/nixos/mandragora/hosts/mandragora-usb/install/format.sh`:

```bash
#!/usr/bin/env bash
# Partition + format a target disk.
# Usage: format.sh /dev/sdX
# Sourceable: format.sh --source-only

set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "$(readlink -f "$0")")/lib.sh"

MIN_BYTES=$(( 30 * 1024 * 1024 * 1024 ))   # 30 GiB
WARN_BYTES=$(( 60 * 1024 * 1024 * 1024 ))  # 60 GiB

_check_size() {
    local bytes="$1"
    if (( bytes < MIN_BYTES )); then
        die "disk too small: $(numfmt --to=iec "$bytes") (minimum 30 GiB)"
    fi
    if (( bytes < WARN_BYTES )); then
        log_warn "disk is small: $(numfmt --to=iec "$bytes") (recommended >= 60 GiB)"
    fi
    return 0
}

_check_existing_partitions() {
    local dev="$1"
    local parts
    parts=$(lsblk -no NAME,TYPE,SIZE "$dev" | awk '$2 == "part" {print}')
    if [[ -n "$parts" ]]; then
        log_warn "disk $dev has existing partitions:"
        echo "$parts" >&2
        echo
        confirm_typed "WIPE" "All data on $dev will be destroyed."
    fi
}

_partition() {
    local dev="$1"
    log_info "Partitioning $dev..."
    sgdisk --zap-all "$dev"
    sgdisk -n 1:0:+1G -t 1:ef00 -c 1:ESP "$dev"
    sgdisk -n 2:0:0   -t 2:8300 -c 2:root "$dev"
    partprobe "$dev"
    sleep 1
}

_format() {
    local dev="$1"
    local p1 p2
    if [[ "$dev" =~ nvme || "$dev" =~ mmcblk ]]; then
        p1="${dev}p1"; p2="${dev}p2"
    else
        p1="${dev}1"; p2="${dev}2"
    fi
    log_info "Formatting $p1 (FAT32)..."
    mkfs.fat -F32 -n ESP "$p1"
    log_info "Formatting $p2 (ext4)..."
    mkfs.ext4 -L mandragora "$p2"
}

_mount() {
    local dev="$1"
    local p1 p2
    if [[ "$dev" =~ nvme || "$dev" =~ mmcblk ]]; then
        p1="${dev}p1"; p2="${dev}p2"
    else
        p1="${dev}1"; p2="${dev}2"
    fi
    mkdir -p /mnt
    mount "$p2" /mnt
    mkdir -p /mnt/boot
    mount "$p1" /mnt/boot
}

main() {
    require_root
    local dev="${1:?usage: format.sh /dev/sdX}"
    [[ -b "$dev" ]] || die "$dev is not a block device"

    local bytes
    bytes=$(blockdev --getsize64 "$dev")
    _check_size "$bytes"
    _check_existing_partitions "$dev"
    _partition "$dev"
    _format "$dev"
    _mount "$dev"

    log_info "Mounted: /mnt (root) and /mnt/boot (ESP)"
}

if [[ "${1:-}" != "--source-only" ]]; then
    main "$@"
fi
```

```bash
chmod +x /etc/nixos/mandragora/hosts/mandragora-usb/install/format.sh
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `nix shell nixpkgs#bats -c bats /etc/nixos/mandragora/hosts/mandragora-usb/tests/install/test_format.bats`

Expected: 4 tests pass.

- [ ] **Step 5: Lint**

Run: `shellcheck /etc/nixos/mandragora/hosts/mandragora-usb/install/format.sh`

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
cd /etc/nixos/mandragora
git add hosts/mandragora-usb/install/format.sh hosts/mandragora-usb/tests/install/test_format.bats
git commit -F - <<'EOF'
install: add format.sh with sgdisk + mkfs

ESP (1 GiB FAT32) + root (rest, ext4 labelled mandragora). Refuses
disks <30 GiB; warns at 30-60 GiB. Requires WIPE confirmation if the
target has existing partitions.
EOF
```

### Task M3.5: Write `install/render-config.sh` (template-driven host generation)

**Files:**
- Create: `hosts/mandragora-usb/install/render-config.sh`
- Create: `hosts/mandragora-usb/install/host-template.nix`
- Create: `hosts/mandragora-usb/tests/install/test_render_config.bats`

- [ ] **Step 1: Write the template**

`/etc/nixos/mandragora/hosts/mandragora-usb/install/host-template.nix`:

```nix
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    @MICROCODE_IMPORT@
  ];

  networking.hostName = "@HOSTNAME@";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  fileSystems."/" = {
    device = "/dev/disk/by-label/mandragora";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };

  hardware.enableRedistributableFirmware = true;
  @GPU_DRIVER_BLOCK@

  users.users.@USER@ = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    shell = pkgs.zsh;
    initialPassword = "mandragora";
  };

  programs.zsh.enable = true;
  networking.networkmanager.enable = true;
  services.openssh.enable = true;

  console.keyMap = "@KEYMAP@";

  system.stateVersion = "25.05";
}
```

- [ ] **Step 2: Write failing tests**

`/etc/nixos/mandragora/hosts/mandragora-usb/tests/install/test_render_config.bats`:

```bash
#!/usr/bin/env bats

setup() {
    RND="$BATS_TEST_DIRNAME/../../install/render-config.sh"
}

@test "render-config.sh is executable" {
    [ -x "$RND" ]
}

@test "_detect_microcode returns intel for GenuineIntel" {
    run bash -c '
        source "'"$RND"'" --source-only
        _detect_microcode_from_vendor GenuineIntel
    '
    [ "$status" -eq 0 ]
    [ "$output" = "intel-ucode" ]
}

@test "_detect_microcode returns amd for AuthenticAMD" {
    run bash -c '
        source "'"$RND"'" --source-only
        _detect_microcode_from_vendor AuthenticAMD
    '
    [ "$status" -eq 0 ]
    [ "$output" = "amd-ucode" ]
}

@test "_detect_gpu intel sets video driver" {
    run bash -c '
        source "'"$RND"'" --source-only
        _detect_gpu_from_id "8086:1234"   # Intel vendor 8086
    '
    [ "$status" -eq 0 ]
    [ "$output" = "intel" ]
}

@test "_detect_gpu amd from 1002 vendor id" {
    run bash -c '
        source "'"$RND"'" --source-only
        _detect_gpu_from_id "1002:abcd"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "amd" ]
}

@test "_detect_gpu unknown returns 'none'" {
    run bash -c '
        source "'"$RND"'" --source-only
        _detect_gpu_from_id "9999:0000"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "none" ]
}

@test "_render_template substitutes placeholders" {
    tmpl=$(mktemp)
    out=$(mktemp)
    cat > "$tmpl" <<-'TPL'
hostname=@HOSTNAME@
user=@USER@
TPL
    run bash -c '
        source "'"$RND"'" --source-only
        _render_template "'"$tmpl"'" "'"$out"'" \
            HOSTNAME=foo USER=m
    '
    [ "$status" -eq 0 ]
    grep -q "hostname=foo" "$out"
    grep -q "user=m" "$out"
    rm -f "$tmpl" "$out"
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `nix shell nixpkgs#bats -c bats /etc/nixos/mandragora/hosts/mandragora-usb/tests/install/test_render_config.bats`

Expected: 7 tests fail.

- [ ] **Step 4: Implement `install/render-config.sh`**

`/etc/nixos/mandragora/hosts/mandragora-usb/install/render-config.sh`:

```bash
#!/usr/bin/env bash
# Generate hardware-configuration.nix and render hosts/<hostname>/default.nix.
# Usage: render-config.sh --hostname H --user U --keymap K [--gpu G]
# Sourceable: render-config.sh --source-only

set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "$(readlink -f "$0")")/lib.sh"

_detect_microcode_from_vendor() {
    case "$1" in
        GenuineIntel) echo "intel-ucode" ;;
        AuthenticAMD) echo "amd-ucode" ;;
        *) echo "none" ;;
    esac
}

_detect_microcode() {
    local vendor
    vendor=$(awk -F: '/^vendor_id/ {gsub(/ /, "", $2); print $2; exit}' /proc/cpuinfo)
    _detect_microcode_from_vendor "$vendor"
}

_detect_gpu_from_id() {
    case "${1%%:*}" in
        8086) echo "intel" ;;
        1002) echo "amd" ;;
        10de) echo "nouveau" ;;
        *)    echo "none" ;;
    esac
}

_detect_gpu() {
    local first_vga
    first_vga=$(lspci -nn | grep -i 'VGA\|3D' | head -n1 | grep -oE '\[[0-9a-f]+:[0-9a-f]+\]' | tr -d '[]')
    [[ -n "$first_vga" ]] && _detect_gpu_from_id "$first_vga" || echo "none"
}

_render_template() {
    local in_file="$1"
    local out_file="$2"
    shift 2
    local content
    content=$(cat "$in_file")
    while [[ $# -gt 0 ]]; do
        local kv="$1"
        local k="${kv%%=*}"
        local v="${kv#*=}"
        content="${content//@${k}@/${v}}"
        shift
    done
    printf '%s' "$content" > "$out_file"
}

_microcode_import() {
    case "$1" in
        intel-ucode) echo '({ ... }: { hardware.cpu.intel.updateMicrocode = true; })' ;;
        amd-ucode)   echo '({ ... }: { hardware.cpu.amd.updateMicrocode = true; })' ;;
        none)        echo '({ ... }: {})' ;;
    esac
}

_gpu_block() {
    case "$1" in
        intel) echo 'hardware.opengl.enable = true; hardware.opengl.extraPackages = with pkgs; [ intel-media-driver ];' ;;
        amd)   echo 'hardware.opengl.enable = true;' ;;
        nouveau) echo 'services.xserver.videoDrivers = [ "nouveau" ]; hardware.opengl.enable = true;' ;;
        none)  echo '# no GPU driver auto-configured' ;;
    esac
}

main() {
    require_root
    local hostname=mandragora-test user=m keymap=us gpu=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --hostname) hostname="$2"; shift 2 ;;
            --user)     user="$2"; shift 2 ;;
            --keymap)   keymap="$2"; shift 2 ;;
            --gpu)      gpu="$2"; shift 2 ;;
            *) die "unknown arg: $1" ;;
        esac
    done

    [[ -z "$gpu" ]] && gpu=$(_detect_gpu)
    local microcode
    microcode=$(_detect_microcode)

    log_info "Hostname:  $hostname"
    log_info "User:      $user"
    log_info "Keymap:    $keymap"
    log_info "Microcode: $microcode"
    log_info "GPU:       $gpu"

    nixos-generate-config --root /mnt --no-filesystems
    log_info "hardware-configuration.nix generated at /mnt/etc/nixos/hardware-configuration.nix"

    local target_dir=/mnt/etc/nixos/mandragora/hosts/$hostname
    mkdir -p "$target_dir"
    cp /mnt/etc/nixos/hardware-configuration.nix "$target_dir/"

    local tmpl_dir
    tmpl_dir=$(dirname "$(readlink -f "$0")")
    _render_template "$tmpl_dir/host-template.nix" "$target_dir/default.nix" \
        "HOSTNAME=$hostname" \
        "USER=$user" \
        "KEYMAP=$keymap" \
        "MICROCODE_IMPORT=$(_microcode_import "$microcode")" \
        "GPU_DRIVER_BLOCK=$(_gpu_block "$gpu")"

    log_info "Rendered: $target_dir/default.nix"
}

if [[ "${1:-}" != "--source-only" ]]; then
    main "$@"
fi
```

```bash
chmod +x /etc/nixos/mandragora/hosts/mandragora-usb/install/render-config.sh
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `nix shell nixpkgs#bats -c bats /etc/nixos/mandragora/hosts/mandragora-usb/tests/install/test_render_config.bats`

Expected: 7 tests pass.

- [ ] **Step 6: Lint**

Run: `shellcheck /etc/nixos/mandragora/hosts/mandragora-usb/install/render-config.sh`

Expected: no errors.

- [ ] **Step 7: Commit**

```bash
cd /etc/nixos/mandragora
git add hosts/mandragora-usb/install/render-config.sh hosts/mandragora-usb/install/host-template.nix hosts/mandragora-usb/tests/install/test_render_config.bats
git commit -F - <<'EOF'
install: add render-config.sh + host template

Detects CPU microcode from /proc/cpuinfo, GPU vendor from lspci,
generates a hardware-configuration.nix, and renders a hosts/<hostname>/
default.nix from a string-substitution template. 7 unit tests via bats.
EOF
```

### Task M3.6: Write `install/install.sh` orchestrator

**Files:**
- Create: `hosts/mandragora-usb/install/install.sh`

- [ ] **Step 1: Implement install.sh**

`/etc/nixos/mandragora/hosts/mandragora-usb/install/install.sh`:

```bash
#!/usr/bin/env bash
# Install mandragora onto a target disk.
# Usage: install.sh [--auto --hostname H --user U --target /dev/sdX --gpu G --keymap K]
#        install.sh                                                          # interactive

set -euo pipefail

DIR="$(dirname "$(readlink -f "$0")")"
# shellcheck source=./lib.sh
source "$DIR/lib.sh"

AUTO=0
HOSTNAME=""
USER_NAME=""
TARGET=""
GPU=""
KEYMAP="us"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)     AUTO=1; shift ;;
        --hostname) HOSTNAME="$2"; shift 2 ;;
        --user)     USER_NAME="$2"; shift 2 ;;
        --target)   TARGET="$2"; shift 2 ;;
        --gpu)      GPU="$2"; shift 2 ;;
        --keymap)   KEYMAP="$2"; shift 2 ;;
        *) die "unknown arg: $1" ;;
    esac
done

require_root

# 1. Try to refresh the in-USB flake from origin (best effort)
if ping -c1 -W3 github.com >/dev/null 2>&1; then
    log_info "Network detected; attempting flake refresh..."
    git -C /etc/nixos/mandragora pull --ff-only origin master 2>/dev/null \
        || git -C /etc/nixos/mandragora pull --ff-only origin main 2>/dev/null \
        || log_warn "git pull skipped or failed; using baked flake."
else
    log_info "No network; using baked flake."
fi

# 2. Detect candidate target disks
log_info "Detecting target disks..."
CANDIDATES=$(bash "$DIR/detect.sh" 2>/dev/null) || die "no candidate target disks"

# 3. Pick the target
if [[ -z "$TARGET" ]]; then
    if (( AUTO )); then die "--auto requires --target"; fi
    log_info "Available targets:"
    select dev in $CANDIDATES "abort"; do
        case "$dev" in
            "" ) log_warn "invalid choice"; continue ;;
            abort) die "aborted by user" ;;
            *) TARGET="$dev"; break ;;
        esac
    done
else
    if ! grep -qx "$TARGET" <<< "$CANDIDATES"; then
        die "target $TARGET is not in the candidate list (boot media filtered out)"
    fi
fi
log_info "Target: $TARGET"

# 4. Prompt for hostname/user/keymap if interactive
if [[ -z "$HOSTNAME" ]]; then
    HOSTNAME="mandragora-$(tr -dc 'a-z0-9' </dev/urandom | head -c6)"
    if (( ! AUTO )); then
        read -rp "Hostname [$HOSTNAME]: " input; HOSTNAME="${input:-$HOSTNAME}"
    fi
fi
if [[ -z "$USER_NAME" ]]; then
    USER_NAME="m"
    if (( ! AUTO )); then
        read -rp "User [$USER_NAME]: " input; USER_NAME="${input:-$USER_NAME}"
    fi
fi
if (( ! AUTO )); then
    read -rp "Keymap [$KEYMAP]: " input; KEYMAP="${input:-$KEYMAP}"
fi

# 5. Format the target
log_info "Formatting $TARGET..."
bash "$DIR/format.sh" "$TARGET"

# 6. Render host config
log_info "Rendering host config..."
local_args=( --hostname "$HOSTNAME" --user "$USER_NAME" --keymap "$KEYMAP" )
[[ -n "$GPU" ]] && local_args+=( --gpu "$GPU" )
bash "$DIR/render-config.sh" "${local_args[@]}"

# 7. Copy the flake into target
log_info "Copying flake..."
mkdir -p /mnt/etc/nixos
cp -a /etc/nixos/mandragora /mnt/etc/nixos/mandragora

# 8. nixos-install
log_info "Running nixos-install..."
nixos-install --no-root-passwd --flake "/mnt/etc/nixos/mandragora#$HOSTNAME"

log_info "Install complete. Reboot, remove the USB, and select the target disk."
```

```bash
chmod +x /etc/nixos/mandragora/hosts/mandragora-usb/install/install.sh
```

- [ ] **Step 2: Lint**

Run: `shellcheck /etc/nixos/mandragora/hosts/mandragora-usb/install/install.sh`

Expected: a few warnings about `select` and `local` outside functions; no errors.

- [ ] **Step 3: Wire scripts into the host's environment**

Edit `/etc/nixos/mandragora/hosts/mandragora-usb/default.nix`. Add at the top of the file (after the opening `{`):

```nix
let
  installPkg = pkgs.writeShellApplication {
    name = "mandragora-install";
    runtimeInputs = with pkgs; [
      bash coreutils util-linux gptfdisk dosfstools e2fsprogs
      nixos-install-tools git iproute2 iputils
    ];
    text = builtins.readFile ./install/install.sh;
  };
  detectPkg = pkgs.writeShellApplication {
    name = "mandragora-detect";
    runtimeInputs = with pkgs; [ bash coreutils util-linux gawk ];
    text = builtins.readFile ./install/detect.sh;
  };
  formatPkg = pkgs.writeShellApplication {
    name = "mandragora-format";
    runtimeInputs = with pkgs; [ bash coreutils util-linux gptfdisk dosfstools e2fsprogs ];
    text = builtins.readFile ./install/format.sh;
  };
in
```

Then add to `environment.systemPackages`:

```nix
    installPkg
    detectPkg
    formatPkg
```

Note: the install scripts `source` `lib.sh` and reference sibling scripts. Because `writeShellApplication` rewrites paths, this approach is imperfect. **Alternative cleaner approach**: bundle all install scripts into a single derivation that copies them to a known prefix:

Replace the `let` block above with:

```nix
let
  installScripts = pkgs.runCommand "mandragora-install-scripts" { } ''
    mkdir -p $out/libexec/mandragora-install
    cp ${./install}/*.sh $out/libexec/mandragora-install/
    cp ${./install}/host-template.nix $out/libexec/mandragora-install/
    chmod +x $out/libexec/mandragora-install/*.sh
    mkdir -p $out/bin
    ln -s $out/libexec/mandragora-install/install.sh        $out/bin/mandragora-install
    ln -s $out/libexec/mandragora-install/detect.sh         $out/bin/mandragora-detect
    ln -s $out/libexec/mandragora-install/format.sh         $out/bin/mandragora-format
    ln -s $out/libexec/mandragora-install/render-config.sh  $out/bin/mandragora-render-config
  '';
in
```

And in `environment.systemPackages`:

```nix
    installScripts
    pkgs.gptfdisk pkgs.dosfstools pkgs.e2fsprogs pkgs.nixos-install-tools pkgs.git
```

- [ ] **Step 4: Rebuild the image**

Run: `nix build /etc/nixos/mandragora#usbImage 2>&1 | tail -10`

Expected: build succeeds.

- [ ] **Step 5: Boot in the refiner and verify install scripts are present**

Run: `nix run /etc/nixos/mandragora#refiner`

Inside the VM after login, verify: `which mandragora-install mandragora-detect mandragora-format`. All three should resolve under `/run/current-system/sw/bin/`.

- [ ] **Step 6: Commit**

```bash
cd /etc/nixos/mandragora
git add hosts/mandragora-usb/install/install.sh hosts/mandragora-usb/default.nix
git commit -F - <<'EOF'
install: add install.sh orchestrator and wire scripts into host

git-pull-before-install (best-effort), interactive prompts for
hostname/user/keymap, target validated against detect.sh's filtered list,
nixos-install --flake ... from the in-USB flake.

Scripts bundled via runCommand so they keep their relative directory
structure (each script sources lib.sh from $(dirname $0)/).
EOF
```

### Task M3.7: End-to-end install in the refiner (manual)

**Files:** none (verification only)

- [ ] **Step 1: Boot the refiner**

Run: `nix run /etc/nixos/mandragora#refiner`

Inside the VM, log in as `m`.

- [ ] **Step 2: Run the install**

```bash
sudo mandragora-install
```

When prompted: select `/dev/vdb` as target, accept defaults for hostname/user/keymap. Watch logs scroll.

Expected: format runs, render-config runs (microcode + GPU detected), copies flake, `nixos-install` succeeds. Final message: "Install complete..."

- [ ] **Step 3: Reboot the VM into the target disk**

Inside the VM: `sudo poweroff`.

Once QEMU exits, restart the refiner with the USB image **omitted** (target disk only). Quickest way: edit `refiner/run-vm.sh` temporarily, comment out the `-drive ${USB_IMG}` line, and re-run. (After the test, revert.)

Actually, simpler: invoke QEMU manually:

```bash
qemu-system-x86_64 \
  -enable-kvm -m 6144 -smp 4 \
  -drive if=pflash,format=raw,readonly=on,file="$MANDRAGORA_OVMF_CODE" \
  -drive if=pflash,format=raw,file=/home/m/Projects/mandragora-usb-refiner/state/OVMF_VARS.fd \
  -drive file=/home/m/Projects/mandragora-usb-refiner/state/target.qcow2,if=virtio,format=qcow2 \
  -netdev user,id=net0 -device virtio-net,netdev=net0 \
  -display none -serial stdio
```

Expected: target boots; login as `m` (password `mandragora`) succeeds; `cat /etc/hostname` shows the chosen hostname (e.g., `mandragora-abc123`); `nixos-version` reports the version.

If boot fails: debug bootloader installation in `nixos-install`. Common cause: ESP not properly mounted at install time.

- [ ] **Step 4: Document M3 success**

No commit. M3 milestone complete: end-to-end install works inside the VM.

---

## M4 — Shared modules with `profile` enum

Refactor zsh and nvim from desktop's existing modules into a shared module location, parameterized on `mandragora.profile`. Validates the pattern on the smallest possible surface before scaling.

### Task M4.1: Add the `mandragora.profile` option module

**Files:**
- Create: `modules/shared/profile.nix`
- Modify: `flake.nix` (import the option in both hosts)
- Modify: `hosts/mandragora-desktop/default.nix`
- Modify: `hosts/mandragora-usb/default.nix`

- [ ] **Step 1: Create the option-declaration module**

```bash
mkdir -p /etc/nixos/mandragora/modules/shared
```

`/etc/nixos/mandragora/modules/shared/profile.nix`:

```nix
{ lib, ... }:

{
  options.mandragora.profile = lib.mkOption {
    type = lib.types.enum [ "desktop" "live" ];
    default = "desktop";
    description = ''
      Which kind of mandragora system this is. Shared modules use this
      to gate desktop-only or live-only behavior.
    '';
  };
}
```

- [ ] **Step 2: Wire the module into both hosts via flake.nix**

Edit `/etc/nixos/mandragora/flake.nix`. Both `nixosConfigurations.mandragora-desktop` and `nixosConfigurations.mandragora-usb` should include `./modules/shared/profile.nix` in their `modules = [ ... ]` list.

- [ ] **Step 3: Set the profile on each host**

Edit `/etc/nixos/mandragora/hosts/mandragora-desktop/default.nix`. Add at the top of the config block:

```nix
  mandragora.profile = "desktop";
```

Edit `/etc/nixos/mandragora/hosts/mandragora-usb/default.nix`. Add at the top of the config block:

```nix
  mandragora.profile = "live";
```

- [ ] **Step 4: Verify both hosts evaluate**

```bash
nix build /etc/nixos/mandragora#nixosConfigurations.mandragora-desktop.config.system.build.toplevel --no-link 2>&1 | tail -5
nix build /etc/nixos/mandragora#usbImage --no-link 2>&1 | tail -5
```

Expected: both build successfully.

- [ ] **Step 5: Commit**

```bash
cd /etc/nixos/mandragora
git add modules/shared/profile.nix flake.nix hosts/mandragora-desktop/default.nix hosts/mandragora-usb/default.nix
git commit -F - <<'EOF'
modules: add shared profile enum

mandragora.profile : "desktop" | "live". Shared modules use this to
gate cross-profile differences. Both hosts now declare their profile.
EOF
```

### Task M4.2: Move zsh config into a shared module

**Files:**
- Create: `modules/shared/zsh.nix`
- Modify: `hosts/mandragora-desktop/default.nix` (or wherever zsh currently lives)
- Modify: `hosts/mandragora-usb/default.nix`
- Modify: `flake.nix`

- [ ] **Step 1: Locate where zsh is currently configured**

Run: `grep -rn "programs.zsh" /etc/nixos/mandragora/hosts /etc/nixos/mandragora/modules 2>/dev/null`

Expected: hits in `hosts/mandragora-desktop/` (likely a `default.nix` or imported submodule) and in `hosts/mandragora-usb/default.nix` (the bare `programs.zsh.enable = true` we added in M1).

Note the desktop's full zsh configuration: aliases, plugins, theme, etc. This is what migrates.

- [ ] **Step 2: Create the shared zsh module**

`/etc/nixos/mandragora/modules/shared/zsh.nix`:

```nix
{ config, pkgs, lib, ... }:

let cfg = config.mandragora; in {
  config = lib.mkMerge [
    {
      programs.zsh.enable = true;
      programs.zsh.enableCompletion = true;

      # Cross-profile shell aliases and config.
      # Lift from hosts/mandragora-desktop/.../zsh.nix (or wherever it lives today)
      # the parts that make sense on both: prompt, history, generic aliases,
      # tools-on-PATH like fzf integration, etc.
      #
      # Concrete migration: copy the current desktop zsh block here, then
      # gate desktop-specific bits with the mkIf blocks below.
    }

    (lib.mkIf (cfg.profile == "desktop") {
      # Desktop-only bits: aliases that reference Hyprland, mpd, keyleds, etc.
      # Move them here from the original location.
    })

    (lib.mkIf (cfg.profile == "live") {
      # Live-only bits: extra prompt info, MOTD-style hints,
      # /persist/npm-global/bin in PATH, etc.
      programs.zsh.shellInit = ''
        export npm_config_prefix="/persist/npm-global"
        export PATH="/persist/npm-global/bin:$PATH"
      '';
    })
  ];
}
```

- [ ] **Step 3: Remove zsh config from the host files**

In `hosts/mandragora-desktop/default.nix` (or its imported zsh submodule), delete the `programs.zsh.*` block. Note any aliases/init code that needs to go to the desktop branch of the shared module before deleting.

In `hosts/mandragora-usb/default.nix`, delete the line `programs.zsh.enable = true;`.

- [ ] **Step 4: Wire the shared module into both hosts via flake.nix**

Edit `flake.nix`. Add `./modules/shared/zsh.nix` to the `modules = [ ... ]` list of both `mandragora-desktop` and `mandragora-usb`.

- [ ] **Step 5: Verify desktop builds (`nixos-rebuild build`, NOT switch)**

```bash
sudo nixos-rebuild build --flake /etc/nixos/mandragora#mandragora-desktop 2>&1 | tail -10
```

Expected: build succeeds. Compare result/sw/bin to the current system to ensure zsh + plugins are still present.

- [ ] **Step 6: Verify USB image builds**

```bash
nix build /etc/nixos/mandragora#usbImage --no-link 2>&1 | tail -5
```

Expected: build succeeds.

- [ ] **Step 7: Smoke-boot the refiner and verify zsh works**

```bash
nix run /etc/nixos/mandragora#refiner
```

Login as `m`. Verify: `echo $SHELL` shows `/run/current-system/sw/bin/zsh`. The prompt should look like the desktop's.

- [ ] **Step 8: Commit**

```bash
cd /etc/nixos/mandragora
git add modules/shared/zsh.nix flake.nix hosts/mandragora-desktop hosts/mandragora-usb/default.nix
git commit -F - <<'EOF'
modules: extract shared zsh module with profile gating

Cross-profile zsh setup now lives in modules/shared/zsh.nix. Desktop-
only aliases/init move into the (cfg.profile == "desktop") branch;
live profile gets npm-global PATH wiring.
EOF
```

### Task M4.3: Move nvim config into a shared module

**Files:**
- Create: `modules/shared/nvim.nix`
- Modify: existing nvim location(s)
- Modify: `flake.nix`

- [ ] **Step 1: Locate current nvim config**

Run: `grep -rn "neovim\|programs.neovim" /etc/nixos/mandragora/hosts /etc/nixos/mandragora/modules 2>/dev/null`

Note the desktop's nvim plugins, LSPs, etc.

- [ ] **Step 2: Create `modules/shared/nvim.nix`**

`/etc/nixos/mandragora/modules/shared/nvim.nix`:

```nix
{ config, pkgs, lib, ... }:

let cfg = config.mandragora; in {
  config = lib.mkMerge [
    {
      programs.neovim = {
        enable = true;
        defaultEditor = true;
        viAlias = true;
        vimAlias = true;
        # Lift from hosts/mandragora-desktop/.../nvim.nix:
        # configuration that's identical on both profiles (general keymaps,
        # default plugins, LSP setup for tools both have).
      };
      environment.systemPackages = with pkgs; [
        # LSPs and tools that make sense on both profiles
        ripgrep fd
      ];
    }

    (lib.mkIf (cfg.profile == "desktop") {
      # Desktop-only nvim plugins/integrations (e.g., wakatime, copilot,
      # GUI-specific things)
    })

    (lib.mkIf (cfg.profile == "live") {
      # Lighter live nvim: maybe skip heavy plugins, smaller LSP set
    })
  ];
}
```

- [ ] **Step 3: Remove nvim config from desktop files and the bare `neovim` from `hosts/mandragora-usb/default.nix`'s `environment.systemPackages`**

- [ ] **Step 4: Wire `modules/shared/nvim.nix` into both hosts in `flake.nix`**

- [ ] **Step 5: Verify desktop builds**

```bash
sudo nixos-rebuild build --flake /etc/nixos/mandragora#mandragora-desktop 2>&1 | tail -10
```

Expected: build succeeds.

- [ ] **Step 6: Verify USB image builds**

```bash
nix build /etc/nixos/mandragora#usbImage --no-link 2>&1 | tail -5
```

Expected: build succeeds.

- [ ] **Step 7: Smoke-boot refiner; verify nvim works**

```bash
nix run /etc/nixos/mandragora#refiner
```

Login, run `nvim --version`, open a file, verify keymaps from the desktop config work.

- [ ] **Step 8: Commit**

```bash
cd /etc/nixos/mandragora
git add modules/shared/nvim.nix flake.nix hosts/
git commit -F - <<'EOF'
modules: extract shared nvim module with profile gating

Same pattern as zsh: cross-profile nvim setup with desktop-only and
live-only branches gated on mandragora.profile.
EOF
```

---

## M5 — First-boot npm + `claude-bootstrap.service`

### Task M5.1: Add npm and node to the live host; configure `/persist/npm-global` prefix

**Files:**
- Modify: `hosts/mandragora-usb/default.nix`

- [ ] **Step 1: Add nodejs to the host's package set**

Edit `/etc/nixos/mandragora/hosts/mandragora-usb/default.nix`. In `environment.systemPackages`, add:

```nix
    nodejs_22
```

(Use whatever LTS-ish version your nixpkgs has.)

- [ ] **Step 2: Set npm prefix env var system-wide**

In the same file, add:

```nix
  environment.variables = {
    npm_config_prefix = "/persist/npm-global";
  };

  environment.sessionVariables = {
    PATH = [ "/persist/npm-global/bin" ];
  };
```

- [ ] **Step 3: Build and smoke-test in refiner**

```bash
nix build /etc/nixos/mandragora#usbImage --no-link
nix run /etc/nixos/mandragora#refiner
```

Login. Verify:

```bash
echo "$npm_config_prefix"        # /persist/npm-global
echo "$PATH" | grep persist/npm   # present
node --version                    # works
npm --version                     # works
```

- [ ] **Step 4: Commit**

```bash
cd /etc/nixos/mandragora
git add hosts/mandragora-usb/default.nix
git commit -F - <<'EOF'
hosts/mandragora-usb: add node + npm with /persist/npm-global prefix

User-level npm globals install into /persist (which survives reboots
once the partition is created). PATH includes that directory.
EOF
```

### Task M5.2: Add `claude-bootstrap.service` (idempotent first-boot npm install)

**Files:**
- Modify: `hosts/mandragora-usb/default.nix`

- [ ] **Step 1: Add the service**

Edit `hosts/mandragora-usb/default.nix`. Add:

```nix
  systemd.services.claude-bootstrap = {
    description = "First-boot install of claude/gemini/qwen CLIs into /persist/npm-global";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [ nodejs_22 coreutils ];
    serviceConfig = {
      Type = "oneshot";
      User = "m";
      RemainAfterExit = false;
      Environment = [ "npm_config_prefix=/persist/npm-global" ];
    };
    script = ''
      set -eu
      mkdir -p /persist/npm-global
      pkgs="@anthropic-ai/claude-code @google/gemini-cli @qwenlm/qwen-cli"
      for pkg in $pkgs; do
        bin=$(basename "$pkg" | tr -d '@/')
        if ! [ -x "/persist/npm-global/bin/$bin" ]; then
          echo "[claude-bootstrap] installing $pkg..."
          npm install -g "$pkg" || echo "[claude-bootstrap] $pkg install failed; will retry next boot"
        else
          echo "[claude-bootstrap] $bin already present, skipping"
        fi
      done
    '';
  };

  # /persist/npm-global must exist before the service runs
  systemd.tmpfiles.rules = lib.mkAfter [
    "d /persist/npm-global 0755 m users - -"
  ];
```

- [ ] **Step 2: Build the image**

```bash
nix build /etc/nixos/mandragora#usbImage --no-link 2>&1 | tail -10
```

Expected: build succeeds.

- [ ] **Step 3: Smoke-test in refiner with network**

The refiner's default user-mode networking has internet. Boot:

```bash
nix run /etc/nixos/mandragora#refiner
```

After login: `journalctl -u claude-bootstrap` (may take 30-60 s). Expected: service ran, attempted npm installs.

If `/persist` isn't mounted (it won't be in the refiner since the qcow2 target is unrelated), the service will write to `/persist/npm-global` on the root filesystem (just a regular dir). That's fine for testing.

After install: verify `/persist/npm-global/bin/claude --version` (or similar; binary names depend on the npm packages). Power off the VM.

- [ ] **Step 4: Boot the same image again, verify idempotence**

```bash
nix run /etc/nixos/mandragora#refiner
```

After login: `journalctl -u claude-bootstrap`. Expected: messages "$bin already present, skipping" for each package.

Note: with `snapshot=on`, the second boot starts from a pristine USB. So this won't actually test idempotence — you'd need persistence. Defer this verification until the `/persist` partition is wired up post-flash.

For now, verify manually that the service script's "if exists, skip" logic is correct by reading the unit file.

- [ ] **Step 5: Commit**

```bash
cd /etc/nixos/mandragora
git add hosts/mandragora-usb/default.nix
git commit -F - <<'EOF'
hosts/mandragora-usb: add claude-bootstrap.service

Idempotent first-boot installer of @anthropic-ai/claude-code,
@google/gemini-cli, @qwenlm/qwen-cli into /persist/npm-global. Skips
silently if offline; retries on next boot. Skips if already installed.
EOF
```

---

## M7 — Sops with USB-specific age key

(M6 is intentionally absent; the GUI was dropped from MVP during brainstorming.)

### Task M7.1: Generate the USB-specific age key and encrypt it

**Files:**
- Create: `secrets/usb-key.age`

- [ ] **Step 1: Generate a fresh age keypair**

```bash
nix shell nixpkgs#age -c age-keygen -o /tmp/usb-key.txt
cat /tmp/usb-key.txt | grep '^# public key' | awk '{print $4}'   # USB recipient
```

Note the public key (starts with `age1...`). This goes into `.sops.yaml`.

- [ ] **Step 2: Encrypt with passphrase**

```bash
nix shell nixpkgs#age -c age -p -o /etc/nixos/mandragora/secrets/usb-key.age /tmp/usb-key.txt
```

You'll be prompted for a passphrase twice. Pick one >= 10 chars; document it in your password manager.

- [ ] **Step 3: Verify the encryption format**

```bash
head -1 /etc/nixos/mandragora/secrets/usb-key.age
```

Expected: `-----BEGIN AGE ENCRYPTED FILE-----`

- [ ] **Step 4: Securely shred the plaintext**

```bash
shred -u /tmp/usb-key.txt
```

- [ ] **Step 5: Commit**

```bash
cd /etc/nixos/mandragora
git add secrets/usb-key.age
git commit -F - <<'EOF'
secrets: add passphrase-encrypted USB-host age key

age -p protected. Decrypted at install time after passphrase prompt;
copied to target system's /persistent/sops/. USB-specific recipient
limits blast radius if the USB is lost (cannot decrypt desktop secrets).
EOF
```

### Task M7.2: Update `.sops.yaml` with USB recipient

**Files:**
- Modify: `.sops.yaml`

- [ ] **Step 1: Read current .sops.yaml**

Run: `cat /etc/nixos/mandragora/.sops.yaml`

Note the existing recipient(s).

- [ ] **Step 2: Add USB recipient**

Edit `/etc/nixos/mandragora/.sops.yaml`. Add the USB age recipient (replace `age1...usb...` with the public key from M7.1):

```yaml
keys:
  - &m_desktop age1...desktop...
  - &m_usb     age1...usb...
creation_rules:
  - path_regex: secrets/usb-.*\.yaml$
    key_groups:
      - age:
          - *m_usb
  - path_regex: secrets/.*\.yaml$
    key_groups:
      - age:
          - *m_desktop
```

(Adjust to match the existing `.sops.yaml` structure; keep desktop secrets only decryptable by the desktop key.)

- [ ] **Step 3: Verify existing secrets still decrypt**

Run: `nix shell nixpkgs#sops -c sops -d secrets/<an-existing-secret>.yaml | head -3`

Expected: decryption succeeds (you'll need access to the desktop's age key).

- [ ] **Step 4: Commit**

```bash
cd /etc/nixos/mandragora
git add .sops.yaml
git commit -F - <<'EOF'
sops: add USB recipient with path-regex isolation

USB host can only decrypt secrets/usb-*.yaml. Desktop continues to own
all other secrets. Lost USB cannot decrypt desktop secrets even if the
passphrase is eventually broken.
EOF
```

### Task M7.3: Add install-time passphrase prompt + age decryption

**Files:**
- Modify: `hosts/mandragora-usb/install/install.sh`

- [ ] **Step 1: Add a function to install.sh that prompts and decrypts**

Edit `install.sh`. After the `# 1. Try to refresh the in-USB flake...` block and before `# 2. Detect candidate target disks`, add:

```bash
# 1.5. Decrypt USB age key if present
USB_KEY_SRC="/etc/nixos/mandragora/secrets/usb-key.age"
USB_KEY_DST="/mnt/persistent/sops/usb-key.txt"
if [[ -f "$USB_KEY_SRC" ]]; then
    log_info "Sops USB key found. Will prompt for passphrase to decrypt."
    DECRYPTED=""
    for attempt in 1 2 3; do
        if DECRYPTED=$(age -d "$USB_KEY_SRC" 2>/dev/null); then
            break
        fi
        log_warn "decryption failed (attempt $attempt of 3)"
        DECRYPTED=""
    done
    if [[ -z "$DECRYPTED" ]]; then
        log_warn "sops key not decrypted; install will continue without USB-host secrets"
    fi
fi
```

After the `# 8. nixos-install` block, add:

```bash
# 9. Place decrypted age key on target
if [[ -n "${DECRYPTED:-}" ]]; then
    mkdir -p "$(dirname "$USB_KEY_DST")"
    printf '%s' "$DECRYPTED" > "$USB_KEY_DST"
    chmod 600 "$USB_KEY_DST"
    log_info "Decrypted age key placed at $USB_KEY_DST"
fi
unset DECRYPTED
```

- [ ] **Step 2: Lint**

Run: `shellcheck /etc/nixos/mandragora/hosts/mandragora-usb/install/install.sh`

Expected: no errors.

- [ ] **Step 3: Verify image still builds**

```bash
nix build /etc/nixos/mandragora#usbImage --no-link 2>&1 | tail -5
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
cd /etc/nixos/mandragora
git add hosts/mandragora-usb/install/install.sh
git commit -F - <<'EOF'
install: prompt for sops passphrase, decrypt USB age key onto target

3 retries; on final failure, install proceeds without sops with a
warning. Decrypted key written to /mnt/persistent/sops/usb-key.txt
mode 600.
EOF
```

### Task M7.4: Add build-time guards as Nix derivations

Spec requirements for build-time checks: hyprland config validity, closure size ceiling, module evaluation under both profiles, sops key encryption format. Each becomes a derivation that must succeed for the build to succeed.

**Files:**
- Create: `modules/shared/build-checks.nix`
- Modify: `flake.nix`

- [ ] **Step 1: Write the build-checks module**

`/etc/nixos/mandragora/modules/shared/build-checks.nix`:

```nix
{ self, nixpkgs, system }:

let
  pkgs = nixpkgs.legacyPackages.${system};

  # Closure-size guard: USB host must be <= 6 GiB
  closureSizeGuard = pkgs.runCommand "usb-closure-size-guard" { } ''
    closure=${self.nixosConfigurations.mandragora-usb.config.system.build.toplevel}
    size_kb=$(${pkgs.nix}/bin/nix path-info -S "$closure" | awk '{print $2}')
    size_gib=$(echo "scale=2; $size_kb / 1024 / 1024" | ${pkgs.bc}/bin/bc)
    echo "USB host closure: $size_gib GiB"
    limit_kb=$(( 6 * 1024 * 1024 ))
    if (( size_kb > limit_kb )); then
      echo "FAIL: closure exceeds 6 GiB ceiling ($size_gib GiB)" >&2
      exit 1
    fi
    touch $out
  '';

  # Sops key must be passphrase-encrypted (age -p), never a raw private key
  sopsKeyGuard = pkgs.runCommand "usb-sops-key-encrypted-guard" { } ''
    if ! [ -f ${self}/secrets/usb-key.age ]; then
      echo "FAIL: secrets/usb-key.age missing" >&2; exit 1
    fi
    head=$(head -1 ${self}/secrets/usb-key.age)
    if [ "$head" != "-----BEGIN AGE ENCRYPTED FILE-----" ]; then
      echo "FAIL: secrets/usb-key.age is not age -p encrypted (got: '$head')" >&2
      exit 1
    fi
    touch $out
  '';

  # Profile enum must evaluate under both values
  profileEvalGuard = pkgs.runCommand "profile-eval-guard" { } ''
    # Touch each host's toplevel; both profiles must build
    desktop=${self.nixosConfigurations.mandragora-desktop.config.system.build.toplevel}
    usb=${self.nixosConfigurations.mandragora-usb.config.system.build.toplevel}
    [ -e "$desktop" ] && [ -e "$usb" ] || { echo "FAIL: one or both hosts didn't build" >&2; exit 1; }
    touch $out
  '';

  # Hyprland config validity (desktop only)
  hyprlandConfigGuard = pkgs.runCommand "hyprland-config-guard" {
    nativeBuildInputs = [ pkgs.hyprland ];
  } ''
    config=${self.nixosConfigurations.mandragora-desktop.config.programs.hyprland.package or "/dev/null"}
    # If the desktop has a generated hyprland.conf, run hyprland --check-config against it
    if [ -f /etc/hyprland.conf ]; then
      ${pkgs.hyprland}/bin/Hyprland --config /etc/hyprland.conf --check-config 2>&1 || {
        echo "FAIL: hyprland config errors" >&2; exit 1; }
    fi
    touch $out
  '';
in
{
  inherit closureSizeGuard sopsKeyGuard profileEvalGuard hyprlandConfigGuard;
}
```

- [ ] **Step 2: Wire guards as flake checks**

Edit `flake.nix`. Add after the `apps` block:

```nix
      checks.${system} = let
        guards = import ./modules/shared/build-checks.nix {
          inherit self nixpkgs system;
        };
      in {
        usb-closure-size = guards.closureSizeGuard;
        usb-sops-key = guards.sopsKeyGuard;
        profile-eval = guards.profileEvalGuard;
        # hyprland-config = guards.hyprlandConfigGuard;  # enable once hyprland module is profile-gated
      };
```

(Skip hyprland for now — runs only after the desktop's hyprland module is profile-gated, which is post-M4.)

- [ ] **Step 3: Run the checks**

Run: `nix flake check /etc/nixos/mandragora 2>&1 | tail -20`

Expected: closure-size, sops-key, and profile-eval guards pass. If closure exceeds 6 GiB, the spec's threshold may need bumping or the host needs trimming.

- [ ] **Step 4: Verify each guard fires when violated**

Manually test failure paths:

```bash
# Test sops-key guard fires by replacing usb-key.age with plaintext
echo "AGE-SECRET-KEY-fake" > /tmp/fake-key
cp /etc/nixos/mandragora/secrets/usb-key.age /tmp/usb-key.age.backup
cp /tmp/fake-key /etc/nixos/mandragora/secrets/usb-key.age
nix flake check /etc/nixos/mandragora 2>&1 | grep -i fail   # expect: "not age -p encrypted"
cp /tmp/usb-key.age.backup /etc/nixos/mandragora/secrets/usb-key.age
shred -u /tmp/fake-key /tmp/usb-key.age.backup
```

Expected: the failure-injection step prints the FAIL message, restoring the file fixes it.

- [ ] **Step 5: Commit**

```bash
cd /etc/nixos/mandragora
git add modules/shared/build-checks.nix flake.nix
git commit -F - <<'EOF'
flake: add build-time guards as nix flake checks

Closure-size ceiling (6 GiB), sops-key encryption format, profile-enum
evaluates for both values. Wired as flake checks; CI / pre-push runs
`nix flake check`.

Hyprland config-check guard scaffolded but disabled until the desktop's
hyprland module is profile-gated (post-M4 follow-up).
EOF
```

---

## M8 — Install hardening

### Task M8.1: Add `--multi-disk` scenario to refiner (extra virtio target disks)

**Files:**
- Modify: `refiner/run-vm.sh`
- Modify: `refiner/lib.sh`

- [ ] **Step 1: Add scenario flag plumbing in run-vm.sh**

Edit `run-vm.sh`. In the argument parser, add:

```bash
SCENARIO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ram) REFINER_RAM="$2"; shift 2 ;;
        --vcpus) REFINER_VCPUS="$2"; shift 2 ;;
        --scenario) SCENARIO="$2"; shift 2 ;;
        --) shift; break ;;
        *) die "unknown arg: $1" ;;
    esac
done
```

Add a function in lib.sh:

```bash
prepare_extra_targets() {
    local count="${1:-0}"
    REFINER_EXTRA_DRIVES=()
    for i in $(seq 1 "$count"); do
        local extra="${REFINER_STATE_DIR}/extra-target-${i}.qcow2"
        rm -f "$extra"
        qemu-img create -f qcow2 "$extra" 30G >/dev/null
        REFINER_EXTRA_DRIVES+=( -drive "file=${extra},if=virtio,format=qcow2" )
    done
}
```

In run-vm.sh's QEMU invocation, splice in the extras:

```bash
EXTRA_TARGETS_COUNT=0
[[ "$SCENARIO" == "multi-disk" ]] && EXTRA_TARGETS_COUNT=2

prepare_extra_targets "$EXTRA_TARGETS_COUNT"

exec qemu-system-x86_64 \
    -enable-kvm \
    -m "$REFINER_RAM" \
    -smp "$REFINER_VCPUS" \
    -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}" \
    -drive "if=pflash,format=raw,file=${REFINER_OVMF_VARS}" \
    -drive "file=${USB_IMG},if=virtio,format=raw,snapshot=on" \
    -drive "file=${REFINER_TARGET},if=virtio,format=qcow2" \
    "${REFINER_EXTRA_DRIVES[@]}" \
    -netdev user,id=net0 \
    -device virtio-net,netdev=net0 \
    -device virtio-rng-pci \
    -display none \
    -serial mon:stdio \
    2>&1 | tee "$REFINER_RUN_LOG"
```

- [ ] **Step 2: Test the scenario manually**

```bash
nix run /etc/nixos/mandragora#refiner -- --scenario multi-disk
```

Inside the VM: `lsblk`. Expected: `vda` (USB), `vdb` (target), `vdc` and `vdd` (extras).

Run `mandragora-detect`. Expected: lists `vdb`, `vdc`, `vdd`; refuses if you try to pick `vda` (boot media).

- [ ] **Step 3: Commit**

```bash
cd /etc/nixos/mandragora
git add refiner/run-vm.sh refiner/lib.sh
git commit -F - <<'EOF'
refiner: add --scenario multi-disk

Attaches two extra blank virtio disks. Validates detect.sh's multi-disk
enumeration and boot-media filtering on the same code path.
EOF
```

### Task M8.2: Add `--small-target` and `--no-network` scenarios

**Files:**
- Modify: `refiner/run-vm.sh`
- Modify: `refiner/lib.sh`

- [ ] **Step 1: Plumb the scenarios**

In `lib.sh`, parameterize target size:

```bash
prepare_target_disk() {
    local size="${1:-$REFINER_TARGET_SIZE}"
    local dst="${REFINER_STATE_DIR}/target.qcow2"
    rm -f "$dst"
    qemu-img create -f qcow2 "$dst" "$size" >/dev/null
    REFINER_TARGET="$dst"
}
```

In `run-vm.sh`:

```bash
TARGET_SIZE="$REFINER_TARGET_SIZE"
NETDEV_ARGS=( -netdev user,id=net0 -device virtio-net,netdev=net0 )

case "$SCENARIO" in
    small-target) TARGET_SIZE=10G ;;
    no-network)   NETDEV_ARGS=() ;;
    "") ;;
    multi-disk) ;;   # handled above
    *) die "unknown scenario: $SCENARIO" ;;
esac

prepare_target_disk "$TARGET_SIZE"
```

Splice `${NETDEV_ARGS[@]}` into the QEMU invocation in place of the inline `-netdev ... -device ...`.

- [ ] **Step 2: Test --small-target**

```bash
nix run /etc/nixos/mandragora#refiner -- --scenario small-target
```

Inside the VM: `sudo mandragora-format /dev/vdb`. Expected: refuses with "disk too small: 10 GiB (minimum 30 GiB)".

- [ ] **Step 3: Test --no-network**

```bash
nix run /etc/nixos/mandragora#refiner -- --scenario no-network
```

Inside the VM: `ping -c1 8.8.8.8` (should fail), then `sudo mandragora-install`. Expected: install proceeds with the baked flake; "No network; using baked flake." in the log.

- [ ] **Step 4: Commit**

```bash
cd /etc/nixos/mandragora
git add refiner/run-vm.sh refiner/lib.sh
git commit -F - <<'EOF'
refiner: add --small-target and --no-network scenarios

small-target verifies format.sh's <30 GB refusal. no-network verifies
the in-USB flake is fully closed (install succeeds offline, proves
closure caching).
EOF
```

### Task M8.3: Add `--clock-skew` and `--bad-passphrase` scenarios

**Files:**
- Modify: `refiner/run-vm.sh`

- [ ] **Step 1: Plumb --clock-skew via QEMU's -rtc flag**

In `run-vm.sh`, add to the `case "$SCENARIO"`:

```bash
    clock-skew) RTC_ARGS=( -rtc base="2010-01-01" ) ;;
```

And declare/use `RTC_ARGS=()` by default. Splice into QEMU invocation.

- [ ] **Step 2: Test --clock-skew**

```bash
nix run /etc/nixos/mandragora#refiner -- --scenario clock-skew
```

Inside the VM: `date`. Expected: shows a date in 2010. Wait 30-60 s; `date` again — should show approximately the real current time (chrony recovered). `journalctl -u chronyd` confirms.

- [ ] **Step 3: --bad-passphrase requires expect; defer to M9 where we add expect anyway**

- [ ] **Step 4: Commit**

```bash
cd /etc/nixos/mandragora
git add refiner/run-vm.sh refiner/lib.sh
git commit -F - <<'EOF'
refiner: add --scenario clock-skew

QEMU -rtc base=2010-01-01 forces the live system to start with a wildly
incorrect clock; chrony is expected to recover within ~60 s.
EOF
```

---

## M9 — `--auto` smoke test

Drives the install non-interactively via `expect`. Verifies the target boots and basic system state is healthy.

### Task M9.1: Create `refiner/auto-install.sh` skeleton

**Files:**
- Create: `refiner/auto-install.sh`

- [ ] **Step 1: Write the skeleton**

`/etc/nixos/mandragora/refiner/auto-install.sh`:

```bash
#!/usr/bin/env bash
# Scripted install + post-install verification.
# Sourced by run-vm.sh when --auto is passed.

set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "$(readlink -f "$0")")/lib.sh"

USB_IMG="${MANDRAGORA_USB_IMG:?}"
OVMF_CODE="${MANDRAGORA_OVMF_CODE:?}"
OVMF_VARS_SRC="${MANDRAGORA_OVMF_VARS:?}"

INSTALL_TIMEOUT="${REFINER_INSTALL_TIMEOUT:-1800}"   # 30 min wall clock

log_info "Starting --auto: scripted install + verify"

ensure_state_dir
allocate_run_log
prepare_ovmf_vars "$OVMF_VARS_SRC"
prepare_target_disk

PASSPHRASE="${REFINER_TEST_PASSPHRASE:-mandragora-test-pass}"

# Stage 1: install via expect
log_info "Stage 1: install"
expect <<EOF
    set timeout $INSTALL_TIMEOUT
    spawn qemu-system-x86_64 \
        -enable-kvm -m 6144 -smp 4 \
        -drive if=pflash,format=raw,readonly=on,file=$OVMF_CODE \
        -drive if=pflash,format=raw,file=$REFINER_OVMF_VARS \
        -drive file=$USB_IMG,if=virtio,format=raw,snapshot=on \
        -drive file=$REFINER_TARGET,if=virtio,format=qcow2 \
        -netdev user,id=net0 -device virtio-net,netdev=net0 \
        -device virtio-rng-pci -display none -serial stdio
    expect "login:"
    send "m\r"
    expect "Password:"
    send "mandragora\r"
    expect "\\\$"
    send "sudo mandragora-install --auto --hostname mandragora-test --user m --target /dev/vdb --keymap us --gpu intel\r"
    expect "passphrase"
    send "$PASSPHRASE\r"
    expect "Install complete"
    send "sudo poweroff\r"
    expect eof
EOF

# Stage 2: boot from target and verify
log_info "Stage 2: verify"
expect <<EOF
    set timeout 300
    spawn qemu-system-x86_64 \
        -enable-kvm -m 6144 -smp 4 \
        -drive if=pflash,format=raw,readonly=on,file=$OVMF_CODE \
        -drive if=pflash,format=raw,file=$REFINER_OVMF_VARS \
        -drive file=$REFINER_TARGET,if=virtio,format=qcow2 \
        -netdev user,id=net0 -device virtio-net,netdev=net0 \
        -display none -serial stdio
    expect "login:"
    send "m\r"
    expect "Password:"
    send "mandragora\r"
    expect "\\\$"
    send "id m && systemctl is-system-running\r"
    expect {
        "running" { exit 0 }
        "degraded" { exit 0 }
        timeout { exit 2 }
    }
EOF

VERIFY_EXIT=$?
if (( VERIFY_EXIT != 0 )); then
    log_error "verify stage failed (exit $VERIFY_EXIT)"
    cp "$REFINER_TARGET" "${REFINER_STATE_DIR}/failed-target-$$.qcow2"
    log_error "target disk preserved at: ${REFINER_STATE_DIR}/failed-target-$$.qcow2"
    exit "$VERIFY_EXIT"
fi

log_info "--auto: PASSED"
exit 0
```

```bash
chmod +x /etc/nixos/mandragora/refiner/auto-install.sh
```

- [ ] **Step 2: Add expect to runtimeInputs**

Edit `refiner/default.nix`. Add `expect` to `runtimeInputs`:

```nix
  runtimeInputs = with pkgs; [
    qemu_kvm
    coreutils
    util-linux
    e2fsprogs
    dosfstools
    gawk
    expect
  ];
```

- [ ] **Step 3: Wire --auto in run-vm.sh**

Edit `run-vm.sh`. Near the top of arg parsing:

```bash
AUTO=0
case "${1:-}" in
    --auto) AUTO=1; shift ;;
esac
```

After all preparation but before the final QEMU exec, branch:

```bash
if (( AUTO )); then
    exec "$(dirname "$(readlink -f "$0")")/auto-install.sh"
fi
```

- [ ] **Step 4: Lint**

Run: `shellcheck /etc/nixos/mandragora/refiner/auto-install.sh /etc/nixos/mandragora/refiner/run-vm.sh`

Expected: no errors. Some warnings about `expect` heredocs may appear; ignore them.

- [ ] **Step 5: Smoke test**

Run: `REFINER_TEST_PASSPHRASE="<your-passphrase-from-M7.1>" nix run /etc/nixos/mandragora#refiner -- --auto`

Expected: stage 1 install completes; stage 2 boots; "PASSED" printed; exit 0.

If timeout: increase `REFINER_INSTALL_TIMEOUT`. If install fails: check `state/run-NNN.log` for the actual error.

- [ ] **Step 6: Commit**

```bash
cd /etc/nixos/mandragora
git add refiner/auto-install.sh refiner/run-vm.sh refiner/default.nix
git commit -F - <<'EOF'
refiner: add --auto scripted smoke test

Two-stage expect script: stage 1 drives mandragora-install
non-interactively against /dev/vdb; stage 2 reboots the VM from the
target disk and asserts systemctl + id m. 30-min wall-clock cap.
On failure, target qcow2 is preserved for inspection.
EOF
```

---

## Cleanup — Retire `appendix/ventoy-usb/`

### Task C1: Cherry-pick remaining diagnostics

**Files:**
- Move: `appendix/ventoy-usb/toolbox/{hw-diag,gpu-stress}.sh` → `hosts/mandragora-usb/diagnostics/{hw-diag,gpu-stress}.sh`

- [ ] **Step 1: Copy diagnostics**

```bash
mkdir -p /etc/nixos/mandragora/hosts/mandragora-usb/diagnostics
cp /etc/nixos/mandragora/appendix/ventoy-usb/toolbox/hw-diag.sh    /etc/nixos/mandragora/hosts/mandragora-usb/diagnostics/
cp /etc/nixos/mandragora/appendix/ventoy-usb/toolbox/gpu-stress.sh /etc/nixos/mandragora/hosts/mandragora-usb/diagnostics/
chmod +x /etc/nixos/mandragora/hosts/mandragora-usb/diagnostics/*.sh
```

- [ ] **Step 2: Wire diagnostics into the host's PATH**

Edit `hosts/mandragora-usb/default.nix`. Replace the existing `installScripts` block to also bundle diagnostics:

```nix
  installScripts = pkgs.runCommand "mandragora-install-scripts" { } ''
    mkdir -p $out/libexec/mandragora-install
    cp ${./install}/*.sh $out/libexec/mandragora-install/
    cp ${./install}/host-template.nix $out/libexec/mandragora-install/
    chmod +x $out/libexec/mandragora-install/*.sh
    mkdir -p $out/libexec/mandragora-diag
    cp ${./diagnostics}/*.sh $out/libexec/mandragora-diag/
    chmod +x $out/libexec/mandragora-diag/*.sh
    mkdir -p $out/bin
    ln -s $out/libexec/mandragora-install/install.sh        $out/bin/mandragora-install
    ln -s $out/libexec/mandragora-install/detect.sh         $out/bin/mandragora-detect
    ln -s $out/libexec/mandragora-install/format.sh         $out/bin/mandragora-format
    ln -s $out/libexec/mandragora-install/render-config.sh  $out/bin/mandragora-render-config
    ln -s $out/libexec/mandragora-diag/hw-diag.sh           $out/bin/mandragora-hw-diag
    ln -s $out/libexec/mandragora-diag/gpu-stress.sh        $out/bin/mandragora-gpu-stress
  '';
```

- [ ] **Step 3: Build and test**

```bash
nix build /etc/nixos/mandragora#usbImage --no-link 2>&1 | tail -5
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
cd /etc/nixos/mandragora
git add hosts/mandragora-usb/diagnostics hosts/mandragora-usb/default.nix
git commit -F - <<'EOF'
hosts/mandragora-usb: bundle hw-diag and gpu-stress as diagnostics

Cherry-picked from the old appendix/ventoy-usb/toolbox/. Available as
`mandragora-hw-diag` and `mandragora-gpu-stress` in the live shell.
EOF
```

### Task C2: Delete the appendix

**Files:**
- Delete: `appendix/ventoy-usb/`

- [ ] **Step 1: Verify nothing in /etc/nixos/mandragora references the appendix**

Run: `grep -rn "appendix/ventoy-usb" /etc/nixos/mandragora --include='*.nix' --include='*.sh' 2>&1`

Expected: no results.

- [ ] **Step 2: Delete the directory**

```bash
rm -rf /etc/nixos/mandragora/appendix/ventoy-usb
rmdir /etc/nixos/mandragora/appendix 2>/dev/null || true
```

- [ ] **Step 3: Verify all builds still succeed**

```bash
sudo nixos-rebuild build --flake /etc/nixos/mandragora#mandragora-desktop 2>&1 | tail -5
nix build /etc/nixos/mandragora#usbImage --no-link 2>&1 | tail -5
```

Expected: both succeed.

- [ ] **Step 4: Commit**

```bash
cd /etc/nixos/mandragora
git add -A appendix/ 2>/dev/null
git rm -rf appendix/ventoy-usb 2>/dev/null
git commit -F - <<'EOF'
appendix: retire ventoy-usb tree

Replaced by hosts/mandragora-usb/ (the live host) plus the refiner.
Diagnostics cherry-picked, install pipeline rebuilt fresh, Ventoy
multiboot retired in favor of a single raw-efi disk image.
EOF
```

---

## Self-review checklist

After completing all milestones, run through this list. Each item maps to a spec requirement.

- [ ] M1: USB image builds (`nix build .#usbImage`)
- [ ] M1: USB image boots in QEMU manually
- [ ] M1: USB image boots on a real 16 GB stick on at least one machine
- [ ] M2: `nix run .#refiner` boots and shows two virtio disks
- [ ] M2: refiner refuses to start without `/dev/kvm`
- [ ] M3: `mandragora-install` works end-to-end in the refiner; target disk boots
- [ ] M3: install does best-effort `git pull` before `nixos-install`
- [ ] M4: `modules/shared/profile.nix` declares the enum; both hosts set it
- [ ] M4: zsh and nvim live in `modules/shared/`; both hosts share them
- [ ] M4: desktop `nixos-rebuild build` still succeeds
- [ ] M5: `claude-bootstrap.service` is idempotent (skips installed packages)
- [ ] M5: live system has `/persist/npm-global/bin` in PATH
- [ ] M7: `secrets/usb-key.age` exists and starts with `-----BEGIN AGE ENCRYPTED FILE-----`
- [ ] M7: `.sops.yaml` declares USB recipient with isolated path regex
- [ ] M7: install prompts for passphrase, retries 3×, falls through with warning
- [ ] M7.4: `nix flake check` runs guards (closure size, sops key format, profile eval) and they all pass
- [ ] M8: refiner `--multi-disk` scenario works
- [ ] M8: refiner `--small-target` scenario causes format.sh to refuse
- [ ] M8: refiner `--no-network` scenario installs offline
- [ ] M8: refiner `--clock-skew` scenario recovers via chrony
- [ ] M9: `nix run .#refiner -- --auto` returns 0 on success
- [ ] M9: `--auto` failure preserves target disk for inspection
- [ ] Cleanup: `appendix/ventoy-usb/` is deleted

If any item fails, fix before declaring v1 done.
