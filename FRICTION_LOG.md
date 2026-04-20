# Mandragora Friction Log: The Technical Hurdles

This document identifies the specific, non-obvious failure points in the transition from Arch to NixOS.

## 1. The "Shebang" & FHS Wall
- **Problem:** NixOS does not have `/bin/bash`, `/usr/bin/env`, or `/usr/bin/python`. 
- **The Friction:** While `zsh script.sh` works, any hotkey or script that calls another script via `./script.sh` will fail because the kernel cannot find the interpreter defined in the shebang.
- **The Fix:** We will use `programs.nix-ld.enable = true;` and `services.envfs.enable = true;` to provide an Arch-like compatibility layer, ensuring your 10-year script library doesn't need a total rewrite on Day 1.

## 2. The "Helpful" Leak (Automounting)
- **Problem:** GUI file managers (Thunar/Dolphin) will show the isolated Shadow drive UUID in the sidebar.
- **Solution:** Explicit `udev` rules (`ENV{UDISKS_IGNORE}="1"`) to hide the drive from the Main profile.

## 3. The "State" & Seafile Integration
- **Problem:** Seafile manages files, but browser profiles and app states are "impure" state.
- **Decision:** We will use Btrfs subvolumes for `~/.config` and `~/.local` to persist this state, while the *configuration* of the apps remains in Nix.

## 4. The "Legacy" Purge
- **Decision:** Custom repos like `dotty` and specialized `st` builds will be dropped or replaced by native Nix alternatives over time. We accept this as part of the migration cost.

## 5. Permissive Power Management
- **Decision:** We will allow `reboot` and `poweroff` to be accessible from both profiles for now, prioritizing ease of movement over the "Trap" complexity.
