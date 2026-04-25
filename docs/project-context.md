---
project_name: 'mandragora-nixos'
user_name: 'm'
date: '2026-04-24'
sections_completed:
  ['technology_stack', 'nix_language_rules', 'impermanence_rules', 'secrets_permissions', 'multi_agent_safety', 'out_of_box', 'workflow_rules', 'anti_patterns']
status: 'complete'
rule_count: 38
optimized_for_llm: true
---

# Project Context for AI Agents

_This file contains critical rules and patterns that AI agents must follow when implementing code in this project. Focus on unobvious details that agents might otherwise miss._

---

## Technology Stack & Versions

- **NixOS** flake — `nixpkgs/nixos-unstable`, system `x86_64-linux`
- **home-manager** (nix-community, follows nixpkgs)
- **sops-nix** (Mic92, follows nixpkgs) — age-encrypted secrets
- **impermanence** (nix-community) — root wiped each boot
- **Hyprland / Wayland** compositor; **NVIDIA proprietary** 570.x beta (RTX 5070 Ti). No X11.
- Single host: `mandragora-desktop` (AMD Ryzen 9 7900X, 32 GB DDR5)
- Repo layout: `flake.nix` → `hosts/mandragora-desktop/` → `modules/{core,desktop,user}/*.nix`
- Non-Nix code lives XDG-mirrored at repo root: `.config/`, `.local/bin/`, `snippets/`, `etc/`
- No JS toolchain — empty `package.json` is intentional

## Critical Implementation Rules

### Nix Language Rules
- Reference non-Nix code via `builtins.readFile ../../.config/<app>/file.conf` or `pkgs.writeShellScript "name" (builtins.readFile ../../.local/bin/script.sh)`. Never embed shell/CSS/Lua/Python via `extraConfig`, `text =`, or heredoc string blocks inside `.nix` files.
- No comments — anywhere. Not in `.nix`, not in shell, not in Lua. Self-documenting names only. Strip existing comments when editing.
- One concern per module file. Prefer `modules/<area>/<thing>.nix` over expanding existing modules past one screen.
- Add packages to `modules/core/globals.nix` for system-wide, or to home-manager (`modules/user/home.nix`) for user-only.

### Impermanence Rules
- Only `/nix`, `/persistent`, `/home/m` (bind-mount of `/persistent/home/m`) survive reboot. Everything else is wiped.
- Any state file outside those paths is broken by design — fix by adding to `modules/core/impermanence.nix`, never by `mkdir`.
- Before adding any service that writes state: check `modules/core/impermanence.nix` and add the path.
- Quick test for any change: "does this survive reboot if I don't touch Nix?" If no → it must be a Nix expression.
- `/etc/nixos/` does NOT survive — git remote is the persistence mechanism. Commit and push before reboot.

### Secrets & Permissions
- Plain-text secrets are forbidden. Use sops-nix with age. Never write `password = "..."`, never log or print files from `secrets/`.
- Age key is at `/persistent/secrets/keys.txt` (root-only, persisted).
- Edit secrets with `sops /etc/nixos/mandragora/secrets/secrets.yaml`. Reference via `config.sops.secrets."path".path`.
- `/etc/nixos/mandragora/` is owned `m:users` — agents edit files directly, no sudo for edits.
- `nixos-rebuild switch` requires sudo — agents cannot run it; tell the user, or instruct them to type `! sudo …`.
- FDE is intentionally off. Never propose enabling it.

### Multi-Agent File Safety
- Never rewrite a file from scratch. Always read current on-disk state first, then targeted edits only.
- A full rewrite has historically dropped working config (e.g., the `home.nix` Firefox/Tridactyl loss on 2026-04-20).
- If a full rewrite is unavoidable: read first, preserve every section not explicitly being replaced, log the rewrite in `~/.ai-shared/TASKS.md`.

### Out-of-the-Box Programs
- Any added program must work on first launch with zero setup steps.
- No plugin managers that bootstrap on first run — declare plugins in Nix (`programs.zsh.plugins`, `programs.neovim.plugins`, `programs.tmux.plugins`).
- No "run this command to finish setup", no first-run wizards. Pre-generate config files via home-manager.
- No `.venv` for Python — use `nix develop`, `nix-shell`, or a `devShells` entry in the flake.

### Workflow Rules
- Edit → Rebuild → Verify → Commit:
  1. Edit files in `/etc/nixos/mandragora/...`
  2. `sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora-desktop` (user runs)
  3. Verify the change actually works
  4. Commit + push (`mandragora-switch` alias automates 2+4 with git sync)
- Remote: `https://github.com/mvrozanti/mandragora-nixos.git`
- Temporary package without rebuild: `nix shell nixpkgs#pkg`. Always follow up by adding to `globals.nix`.
- Append to `SESSIONS.md` at end of every session (what was done, what broke, friction, next steps).

### Critical Don't-Miss Rules
- Don't propose imperative fixes (`pacman`, `chmod`, `systemctl enable`, manual file creation in `/etc`). All solutions must be Nix expressions.
- Don't propose X11 fallbacks, even when NVIDIA + Wayland is rough. The constraint is firm.
- Don't propose disabling SSH key-only auth or the SSH daemon defaults.
- Don't add hidden state directories under `/var/lib/<thing>` without also adding the path to impermanence.
- Don't conflate `AGENTS.md` (canonical hard rules) with `DECISIONS.md` (resolved choices) or `FRICTION_LOG.md` (open issues). When in doubt, AGENTS.md wins.
- Reference docs by file when answering: `AGENTS.md`, `CLAUDE.md`, `DECISIONS.md`, `atlas/non-negotiables.md`, `modules/core/impermanence.nix`.

---

## Usage Guidelines

**For AI Agents:**
- Read this file before implementing any code.
- Follow ALL rules exactly as documented. When in doubt, prefer the more restrictive option.
- If a proposed change conflicts with a rule, surface the conflict to the user — do not silently bend the rule.
- Update this file if a new pattern emerges that future agents must respect.

**For Humans:**
- Keep this file lean — it's loaded into agent context, every line costs tokens.
- Update when the technology stack changes (nixpkgs branch, compositor, GPU driver).
- Review whenever `AGENTS.md` or `CLAUDE.md` changes — those are the upstream truth, this is the distillate.
- Remove rules that become obvious or redundant over time.

Last Updated: 2026-04-24
