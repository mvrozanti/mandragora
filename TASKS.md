# Unified AI Task Bridge

This file persists tasks, states, and workflows across different AI agents (Claude, Gemini, etc.).

## Active Tasks
- Clean up partial Ollama model blobs in `/var/lib/private/ollama/models/blobs/` to reclaim space from cancelled downloads.
- Phase 7: Audit and Nixify scripts from `~/projects/mandragora/.local/bin/` (unclaimed)
- Phase 6: Seafile client config (unclaimed)
- Phase 5: Shadow profile LUKS2 setup (deferred — dedicated session required)

## Completed Tasks
- [2026-04-21] Create `nixos-clean` command to prune generations and optimize store (Gemini)
- [2026-04-19] Set up initial NixOS Hyprland config (Claude)
- [2026-04-19] Investigate Gemma crash (Gemini)
- [2026-04-19] Upgrade local MCP server to support multiple models (Gemma 3 + DeepSeek R1 70B)
- [2026-04-19] Pull DeepSeek R1 70B Abliterated (Gemini)
- [2026-04-19] Configure MCP integration for local Ollama instance (Claude/Gemini)
- [2026-04-20] Add super+E / super+shift+E / super+ctrl+E hyprland keybinds (dwindle rotate equiv) (Claude)
- [2026-04-20] Install gemini-cli to home.packages (Claude)
- [2026-04-20] Fix Tridactyl native messenger registration via programs.firefox.nativeMessagingHosts (Claude)
- [2026-04-20] Deploy unugly.css theme to ~/.config/tridactyl/themes/ — fixes dark gray hint colors (Claude)
- [2026-04-20] Restructure repo: killed snippets/, all files moved to XDG-mirrored dirs (.config/, .local/bin/, etc/) (Claude)
- [2026-04-20] Phase 6: earlyoom enabled (services.earlyoom, 5%/10% thresholds) — done by another agent

## Retrospectives & Lessons Learned
- **Config Distribution (2026-04-19):** Gemini incorrectly *moved* `GEMINI.md` out of the version-controlled `/etc/nixos/mandragora` repo and replaced it with a symlink to `~/.ai-shared`. **Lesson:** AIs must **COPY** configuration files from version-controlled repositories into the `~/.ai-shared` bridge, never *move* them and replace them with symlinks, to preserve Git tracking.
- **Full-File Rewrite Clobber (2026-04-20):** An agent rewrote `modules/user/home.nix` from scratch, dropping `programs.firefox` (with `nativeMessagingHosts`) that a prior agent had added in the same session. Firefox became uninstalled. **Lesson:** NEVER rewrite a file from scratch without reading its current on-disk state first. Always use targeted edits (append, patch specific blocks). If a full rewrite is truly necessary, read the file, diff mentally against your intent, and preserve every section you are not explicitly replacing.

---
*Append new tasks or state updates below.*
- [2026-04-22] Change Hyprland resize binding to Alt+RMB (Gemini)
- [2026-04-25] Unified memory store: moved Claude's per-agent memory dir into `~/.ai-shared/memory/`; symlinked Claude harness path back. AGENTS.md / repo-level CLAUDE.md / repo-level GEMINI.md updated so both agents start with the same accumulated knowledge. Gemini now MUST read `~/.ai-shared/memory/MEMORY.md` at session start (no auto-injection). (Claude)

## Active: mandragora-usb + refiner (2026-04-25, Claude)

**Spec:** `/etc/nixos/mandragora/docs/superpowers/specs/2026-04-25-mandragora-usb-refiner-design.md` (commit `a7e8d1eb`)
**Plan:** `/etc/nixos/mandragora/docs/superpowers/plans/2026-04-25-mandragora-usb-refiner.md` (commit `475b82da`)

### Progress through 2026-04-25 evening

M1 (minimal USB host) and M2 (refiner harness) are DONE. `nix run .#refiner`
boots the USB image in QEMU+KVM with a blank 40 GB target disk attached;
login prompt reaches `mandragora-usb login:` in ~15s.

Commits:
- `c2f79d41` M1.1 flake: add nixos-generators input
- `5a252d49` M1.2 hosts/mandragora-usb: minimal skeleton
- `f47a7a41` M1.3 wire mandragora-usb into nixosConfigurations
- `862a7cdc` M1.4 packages.usbImage via nixos-generators raw-efi
- `76fa4e34` M1.5 fix: enableAllHardware + initrd emergency access
- `f8b8467d` M1.6 stub /persist mount with nofail
- `2f7d981b` M2.1 refiner/lib.sh
- `b589028a` M2.2 refiner/run-vm.sh
- `6c986feb` M2.3 wrap refiner as flake app

**Bugs caught by VM testing (deviations from plan):**
- M1.3 wireless conflict: NetworkManager forces `wireless.enable = true` (NM
  manages wpa_supplicant via DBus). Plan's `wireless.enable = false` had
  to be dropped, not mkForce'd, so wireless still works on portable USB.
- M1.5 boot hang: `nixos-generators raw-efi` only adds `uas` to initrd
  modules. With QEMU's `-drive if=virtio` the disk is invisible (no
  virtio_blk) and boot hangs 90s waiting for `/dev/disk/by-label/nixos`
  before dropping to (locked-root) emergency mode. Fix:
  `hardware.enableAllHardware = true` + `boot.initrd.systemd.emergencyAccess = true`.
- M1.3 step 3 (toplevel build of `mandragora-usb`) is impossible; that
  config has no `fileSystems` or bootloader (those come from
  nixos-generators). `nix flake show` covers eval; the actual buildable
  target is `#usbImage`. Skipped step 3.
- M2.3 `nix run` failed twice: (a) `flake.nix` references a new file —
  must `git add --intent-to-add` before nix sees it; (b) wrapper had
  `exec ${./run-vm.sh}` which puts the script alone in /nix/store/, so
  its `dirname`-relative source for `lib.sh` finds nothing. Fix: bundle
  both scripts via `pkgs.runCommand` into one store dir.

**Deprecation notice:** `nixos-generators` is upstreamed into nixpkgs as
of NixOS 25.05 (now `system.image` in modern flow). Plan still uses
`nixos-generators`; refactor candidate post-MVP.

### Skipped / deferred

- **M1.7** (flash to real 16 GB USB and boot a machine): explicit user
  decision — no longer a hard exit gate. Do when convenient.
- **M1.8** (manual /persist partition on flashed USB): depends on M1.7.

### Next when resuming

Start **M3.1** — install pipeline minimal (`hosts/mandragora-usb/install/`
scripts: lib.sh, detect.sh, format.sh, render-config.sh, install.sh).
M3.7 needs human in the loop for the first end-to-end install run inside
the refiner.

**Decisions beyond the spec/plan (still apply):**
- Stay on `master`, no feature branch.
- Hybrid execution: mechanical tasks inline, substantive via subagent.
- Strip plan-comments at commit (CLAUDE.md Rule #3).
- `nix-instantiate --parse <file>` after every .nix edit (Rule #11).
- Lock identity flaw still unfixed; coarse "someone is working" signal.
