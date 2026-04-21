# Mandragora Friction Log: The Technical Hurdles

This document identifies the specific, non-obvious failure points in the transition from Arch to NixOS.

## 1. The "Shebang" & FHS Wall
- **Problem:** NixOS does not have `/bin/bash`, `/usr/bin/env`, or `/usr/bin/python`. 
- **The Friction:** While `zsh script.sh` works, any hotkey or script that calls another script via `./script.sh` will fail because the kernel cannot find the interpreter defined in the shebang.
- **The Fix:** We will use `programs.nix-ld.enable = true;` and `services.envfs.enable = true;` to provide an Arch-like compatibility layer, ensuring your 10-year script library doesn't need a total rewrite on Day 1.

## 2. The "State" & Seafile Integration
- **Problem:** Seafile manages files, but browser profiles and app states are "impure" state.
- **Decision:** We will use Btrfs subvolumes for `~/.config` and `~/.local` to persist this state, while the *configuration* of the apps remains in Nix.

## 4. The "Legacy" Purge
- **Decision:** Custom repos like `dotty` and specialized `st` builds will be dropped or replaced by native Nix alternatives over time. We accept this as part of the migration cost.

## 5. Permissive Power Management
- **Decision:** We will allow `reboot` and `poweroff` to be accessible from both profiles for now, prioritizing ease of movement over the "Trap" complexity.

## 6. super+shift+N moves focused window — watch out on non-default workspaces
- **Problem:** `$mainMod SHIFT, N` is bound to `movetoworkspace, N+1`. If a non-terminal window (e.g. vesktop/Discord) is focused and the user presses super+shift+3 intending to open kitty, the focused window gets moved to workspace 4 (kitty's workspace) instead.
- **Observed:** While on the Discord workspace, pressing super+shift+3 moved the Discord window to workspace 4 alongside the new kitty window.
- **Root cause:** The movetoworkspace binds operate on whatever window is currently focused — there's no guard for "only move if a terminal is focused."
- **To investigate:** Consider whether smart-launch for kitty (super+3) should also be the bind for super+shift+3, or add a guard. Also note: the Discord workspace number was still unresolved when this was logged (vesktop windowrule was being debugged).
