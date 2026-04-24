# CLAUDE.md — Mandragora NixOS

**Read `AGENTS.md` first.** It is the routing table for every session. This file adds Claude Code-specific context on top of it.

---

## What This Repo Is

Declarative NixOS configuration for the Mandragora workstation (AMD Ryzen 9 7900X, RTX 5070 Ti, 32GB DDR5). Everything about this system lives here. If it is not declared in Nix, it does not survive a reboot.

---

## Programs Must Be Ready Out of the Box

Any program added to this system must work correctly from first launch with zero manual setup steps. This means:

- **No plugin managers that bootstrap on first run** — declare all plugins in Nix (`programs.zsh.plugins`, `programs.neovim.plugins`, `programs.tmux.plugins`, etc.)
- **No "run this command to finish setup"** — all post-install steps go in Nix activation or home-manager
- **No first-run wizards** — disable or pre-configure them declaratively
- **Config files must exist before the program runs** — home-manager generates them; never rely on the program creating its own defaults

When adding any new tool: "Would a fresh boot user have to do anything before using this?" If yes, that setup belongs in Nix.

---

## The Impermanence Rule — Read This Carefully

Every boot, `/` (root) is deleted and recreated from a clean Btrfs snapshot. Only these survive:

| What | Path | Lifecycle |
|---|---|---|
| Packages + system | `/nix` | Permanent (Nix store) |
| **Entire home** | `/home/m` | **Permanent** — whole directory bind-mounted from `/persistent/home/m` |
| System state | `/persistent` | Permanent Btrfs subvolume |
| Everything else | `/`, `/tmp`, `/run` | **Wiped on every boot** |

`/home/m` is the island. Anything written there survives. `/etc/` (including `/etc/nixos/`) does not — the git remote is the persistence mechanism for the config source. **Commit and push before rebooting.**

**The practical consequence**: if you `sudo` create a file somewhere, enable a systemctl unit, or install a package imperatively — it is gone next boot. Every single change must be a Nix expression. Verify this is understood before proposing any fix.

**Quick test for any proposed change**: "Does this survive reboot if I don't touch Nix?" If no → it must go in the flake.

---

## Multi-Agent File Safety Rule

**Never rewrite a file from scratch.** Other agents may have edited the same file earlier in the session or in a prior session. Always read the current on-disk state before making any change. Use targeted edits — patch only the blocks relevant to your task. A full rewrite silently clobbers every other agent's work.

If a full rewrite is unavoidable:
1. Read the file first.
2. Preserve every section you are not explicitly replacing.
3. Log the rewrite in `~/.ai-shared/TASKS.md`.

This rule exists because on 2026-04-20, a rewrite of `home.nix` dropped `programs.firefox` (with Tridactyl native messaging), making Firefox unlaunchable.

---

## The Edit → Rebuild → Verify → Commit Workflow

```
1. Edit:    vim /etc/nixos/mandragora/modules/...
2. Rebuild: sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora-desktop
3. Verify:  test the change actually works
4. Commit:  cd /etc/nixos/mandragora && git add -A && git commit && git push
```

Remote: `https://github.com/mvrozanti/mandragora-nixos.git`

The alias `mandragora-switch` (to be implemented in zsh config) will automate steps 2+4 with git sync.

---

## File Permissions & Sudo Context

- `/etc/nixos/mandragora/` is owned by `m:users` — Claude Code can edit files directly
- `nixos-rebuild switch` requires `sudo` — Claude Code cannot run this; tell the user to run it
- To run sudo commands from Claude Code prompt: user types `! sudo <command>`

---

## Language Purity Rule

Non-Nix code (shell, Python, CSS, Lua) lives in XDG-mirrored directories at the repo root and is referenced from `.nix` files:
- `builtins.readFile ../../.local/bin/script.sh` — scripts/binaries
- `builtins.readFile ../../.config/<app>/file.conf` — app configs
- `pkgs.writeShellScript "name" (builtins.readFile ...)` — compile to runnable Nix store path

Never embed shell/config strings directly in `.nix` files via `extraConfig`, `postShellInit`, or similar. No comments in any code. Logic must be self-documenting.

---

## Non-Negotiables (Hard Constraints)

Full list: `AGENTS.md` (canonical). Summary:

- All changes are Nix expressions — no imperative commands (`pacman`, `chmod`, `systemctl enable`) as solutions
- No comments in code
- No plain-text secrets — sops-nix with age encryption only
- NVIDIA + Wayland only — no X11 fallback
- Any change touching `/home` must be reconciled with `modules/core/impermanence.nix`

---

## Key Files Quick Reference

| Purpose | File |
|---|---|
| AI routing table | `AGENTS.md` |
| All resolved decisions | `DECISIONS.md` |
| Hard constraints | `AGENTS.md` (canonical), landmark at `atlas/non-negotiables.md` |
| Hardware specs | `atlas/hardware.md` |
| What persists across reboots | `modules/core/impermanence.nix` |
| System packages + nix-ld | `modules/core/globals.nix` |
| Hyprland compositor setup | `modules/desktop/hyprland.nix` |
| User home + keybindings + mpd | `modules/user/home.nix` |
| Scripts and binaries | `.local/bin/` |
| App configs | `.config/<app>/` |
| Session history | `SESSIONS.md` |

---

## Memory System

User preferences and project state persist across conversations at:

```
~/.claude/projects/-home-m/memory/
```

Index: `~/.claude/projects/-home-m/memory/MEMORY.md`

Update memories when you learn something important about the user or system that would help future sessions. Always check for stale memories before acting on them.

---

## Temporary Package Installation (User Instruction)

When the user needs a package immediately without rebuilding:
```bash
nix shell nixpkgs#packagename
```
This is ephemeral — closed when the shell exits. Always follow up by adding the package to `modules/core/globals.nix` for permanence.

---

## Session Log

Append to `SESSIONS.md` at the end of every session. Include: what was done, what broke, what friction was encountered, and what is next.

---

## SSH Key Import Process

When the user is ready to import SSH keys into sops:

```bash
# 1. Edit the secrets vault
sops /etc/nixos/mandragora/secrets/secrets.yaml

# 2. Add under 'ssh:' key:
#    id_ed25519: |
#      -----BEGIN OPENSSH PRIVATE KEY-----
#      ...
#      -----END OPENSSH PRIVATE KEY-----

# 3. In secrets.nix, add to sops.secrets:
#    "ssh/id_ed25519" = { path = "/home/m/.ssh/id_ed25519"; owner = "m"; mode = "0600"; };
#    "ssh/id_ed25519.pub" = { path = "/home/m/.ssh/id_ed25519.pub"; owner = "m"; mode = "0644"; };

# 4. Rebuild
```

The age decryption key is at `/persistent/secrets/keys.txt` (root-only, survives reboots).


## Old Reference Repo

The user's previous Arch+bspwm configuration lives at:
- Local clone: `~/projects/mandragora`
- GitHub: `https://github.com/mvrozanti/mandragora`

When migrating configs (zsh, tmux, neovim, etc.), fetch from there. Always translate to Nix — do not copy imperative configs verbatim.
