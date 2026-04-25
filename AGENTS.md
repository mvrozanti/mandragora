# AGENTS.md — Mandragora Universal Context

This file is the single source of truth for all AI agents (Claude, Gemini, local LLMs). Every agent reads this first. Agent-specific addons live in their own files.

---

## Who You Are Working With

**User:** m (mvrozanti)
**System:** Mandragora — NixOS workstation (AMD Ryzen 9 7900X, RTX 5070 Ti 16GB, 32GB DDR5)
**Background:** Linux power user, 10+ years on Arch+bspwm. Now migrating that entire setup to declarative NixOS+Hyprland.
**Comfort level:** Expert in Linux, ricing, and system administration. Still learning the Nix language and NixOS module system specifically.
**Communication:** Direct and technical. ELI5 only for NixOS-specific concepts (declarative paradigm, module system, flakes). No filler.

---

## The System Config

**Repo:** `/etc/nixos/mandragora/` — git-tracked, owned by `m:users`
**GitHub remote:** `https://github.com/mvrozanti/mandragora-nixos.git`
**Old Arch dotfiles (reference):** `/home/m/projects/mandragora/` and `https://github.com/mvrozanti/mandragora`

---

## Non-Negotiables (Absolute Rules)

These are invariants. Violating any of them is unacceptable regardless of how much easier it would make a task.

**1. Declarative Supremacy**
Every system change is a Nix expression. No `pacman -S`, no `chmod`, no `systemctl enable` as solutions. If it is worth changing, it gets Nixified. Reproducibility from scratch in < 30 minutes is a hard requirement.

**2. Language Purity**
Non-Nix code (shell, Python, CSS, Lua) lives in XDG-mirrored directories at the repo root and is referenced from `.nix` files via `builtins.readFile` or `pkgs.writeShellScript`. Never embed config strings inside `.nix` files via `extraConfig` or similar string blocks.

**3. No Comments in Code**
Logic must be self-documenting through clean naming and structure. Existing comments must be removed, not preserved.

**4. Zero Plain-Text Secrets**
sops-nix with age encryption for everything. Never propose a Nix module with `password = "..."`. Never print or log anything from `secrets/`.

**5. Impermanence Awareness**
The root filesystem is wiped on every boot. Only `/nix`, `/persistent`, and `/home/m` (bind-mounted from `/persistent/home/m`) survive. Any proposed change that creates state outside these paths is broken by design and must be rejected. Check `modules/core/impermanence.nix` before touching anything in `/home`.

**6. NVIDIA + Wayland Only**
No X11 fallback. The system runs Hyprland/Wayland with proprietary NVIDIA drivers (RTX 5070 Ti, beta 570.x).

**7. No .venv for Python Projects**
Never create or use `.venv` directories for Python virtual environments. Use `nix develop`, `nix-shell`, or `devShells` for all Python dependency management. Express dependencies declaratively via a flake devShell or `shell.nix`.

**8. Programs Must Be Ready Out of the Box**
Any program added to this system must work correctly from first launch with zero manual setup steps. No plugin managers that bootstrap on first run, no "run this command to finish setup", no first-run wizards. Config files must exist before the program runs.

**9. No Full Disk Encryption**
FDE is explicitly not wanted. The main drive is intentionally unencrypted. Never propose or recommend enabling FDE.

---

## The Impermanence Rule (Expanded)

| Survives reboot | Path | Why |
|---|---|---|
| Packages + system | `/nix` | Nix store |
| User home | `/home/m` | Bind-mount from `/persistent/home/m` |
| System state | `/persistent` | Dedicated btrfs subvolume |
| **Everything else** | `/`, `/tmp`, `/run` | **Wiped every boot** |

Before proposing any fix: ask "does this survive reboot without touching Nix?" If no — it must go in the flake.

---

## Multi-Agent File Safety Rule

**Never rewrite a file from scratch.** Other agents may have edited the same file earlier in the session or in a prior session. Always read the current on-disk state before making any change. Use targeted edits — patch only the blocks relevant to your task. A full rewrite silently clobbers every other agent's work.

If a full rewrite is unavoidable:
1. Read the file first.
2. Preserve every section you are not explicitly replacing.
3. Log the rewrite in `~/.ai-shared/TASKS.md`.

**Why this rule exists:** on 2026-04-20, a full rewrite of `modules/user/home.nix` dropped the `programs.firefox` block (with Tridactyl native-messaging wiring), making Firefox unlaunchable until restored from git. The rule is incident-driven, not theoretical.

---

## Security Model

- `/etc/nixos/mandragora/` owned by `m:users` — agents can edit files directly
- `nixos-rebuild switch` requires sudo
- Main drive is **not encrypted** (intentional)
- SSH daemon disabled by default; key-only auth enforced if enabled
- DNS-over-TLS via systemd-resolved (Cloudflare + Quad9 fallback)

---

## Key Files Quick Reference

| Purpose | File |
|---|---|
| Hard constraints | This file (`AGENTS.md`) |
| All resolved decisions | `DECISIONS.md` |
| What persists across reboots | `modules/core/impermanence.nix` |
| System packages + nix-ld | `modules/core/globals.nix` |
| Hyprland compositor setup | `modules/desktop/hyprland.nix` |
| User home + keybindings + mpd | `modules/user/home.nix` |
| Scripts and binaries | `.local/bin/` |
| App configs | `.config/<app>/` |
| Session history | `SESSIONS.md` |

---

## The Edit → Rebuild → Verify → Commit Workflow

```
1. Edit    /etc/nixos/mandragora/...
2. Rebuild + Commit + Push: mandragora-switch [optional commit message]
3. Verify  test the change actually works
```

`mandragora-switch` (defined in `.local/bin/mandragora-switch.sh`, exposed via
`modules/user/home.nix`) does, in order: `git fetch` → rebase if behind →
`git add -A` → open staged-diff editor for commit message (skip with `!`) →
`sudo nixos-rebuild switch` → `git push`. Aliases in `modules/user/zsh.nix`:
`switch` / `nrc` / `rebuild` → `mandragora-switch`; `nrs` → `mandragora-switch !`
(skip diff editor); `nrp` → `mandragora-commit-push` (commit + push only, no
rebuild — used when only docs/markdown changed).

If `mandragora-switch` is unavailable (e.g., during initial install or
recovery), the manual equivalent is:

```
sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora-desktop \
  && cd /etc/nixos/mandragora && git add -A && git commit && git push
```

---

## Per-Agent Policy Variances

These are explicit policy differences between agents. They live here (not
hidden in agent-specific files) so a human reading AGENTS.md can audit them.

- **Gemini CLI** is mandated to run `mandragora-switch` immediately after
  every file modification, with autonomous commit explicitly authorized for
  this purpose (see `GEMINI.md`). Claude Code and other agents follow the
  default rule: do not commit without explicit user instruction.
- **Claude Code** has a memory system at `~/.claude/projects/-home-m/memory/`
  for cross-session preference persistence (see `CLAUDE.md`). Other agents
  use `~/.ai-shared/TASKS.md` for handoff state instead.

---

## AI Bridge (`~/.ai-shared`)

All agents share context through:
- `~/.ai-shared/TASKS.md` — active goals, completed work, handoffs
- `~/.ai-shared/skills/` — multi-agent workflow definitions
- `~/.ai-shared/rules/` — additional constraints
- `~/.ai-shared/templates/` — reusable patterns

When you discover a system quirk or define a new pattern, document it in the bridge so other agents can read it.
