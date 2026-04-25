# mandragora-nixos — Development Guide

**Date:** 2026-04-25

## Prerequisites

- The Mandragora workstation already running NixOS with this configuration.
  (For a fresh install, see [deployment-guide.md](./deployment-guide.md).)
- Sudo access to run `nixos-rebuild switch`.
- Age private key at `/persistent/secrets/keys.txt` (auto-imported during
  install; see `install/bootstrap-age-key.sh`).
- `git`, `nix` with `flakes` and `nix-command` features enabled (already on
  via `modules/core/globals.nix`).

## Repository Locations

The same git working tree is reachable at two paths:

| Path                          | Purpose                                                       |
| ----------------------------- | ------------------------------------------------------------- |
| `/etc/nixos/mandragora/`      | Canonical path consumed by `nixos-rebuild --flake`            |
| `/persistent/mandragora/`     | Bind-mounted alias; convenient when working from `/persistent` |

Both point at the exact same files. Edit anywhere; commit anywhere.

Owner: `m:users`. No sudo is required to edit files. Sudo _is_ required to
rebuild.

Remote: `https://github.com/mvrozanti/mandragora-nixos.git`.

## The Edit → Rebuild → Verify → Commit Workflow

```
1. Edit    /etc/nixos/mandragora/<file>
2. Rebuild sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora-desktop
3. Verify  test the changed feature directly
4. Commit  git add -A && git commit && git push
```

The `mandragora-switch` zsh alias automates steps 2 + 4 with git sync.

### Why "commit before reboot"

`/etc/nixos/` does **not** survive impermanence wipes — only the git remote
is the persistence mechanism for the configuration source. **Always commit
and push before rebooting.** A commit that exists only in a working tree
under `/etc/nixos/` will be gone after the next boot if it has not been
pushed to the persistent path or to the remote.

> Note: the bind-mount from `/persistent/mandragora/` to `/etc/nixos/mandragora/`
> means files actually live under `/persistent`, so they _do_ survive reboot
> on disk. But the discipline of "commit before reboot" remains: it ensures
> remote backup and protects against accidental wipes of the persistent
> subvolume.

## Common Tasks

### Add a system-wide package

1. Open `modules/core/globals.nix`.
2. Add the package name to `environment.systemPackages`.
3. Rebuild.

For an ephemeral try-before-you-commit:

```bash
nix shell nixpkgs#<package>
```

This is closed when the shell exits. **Always** follow up by adding the
package to `globals.nix` for permanence.

### Add a user-only package

1. Open `modules/user/home.nix`.
2. Add the package to `home.packages`.
3. Rebuild.

### Add a new module

1. Create `modules/<area>/<thing>.nix` — pick the closest area
   (`core`/`desktop`/`user`/`audits`).
2. Keep it focused on one concern; aim for ≤ one screen of code.
3. Add the import line to `hosts/mandragora-desktop/default.nix`.
4. Rebuild.

### Add a non-Nix file (shell script, config, lua, css)

The "language purity" rule forbids embedding non-Nix bodies inside `.nix`
files. Instead:

1. Place the file in its XDG-mirrored location at the repo root:
   - Shell script that you'd call from a keybind: `.local/bin/<name>.sh`.
   - App config: `.config/<app>/<file>.conf`.
   - Helper called by another script or `programs.*`: `snippets/<name>.<ext>`.
2. In the relevant `.nix` module, reference it via:
   - `builtins.readFile ../../.config/<app>/<file>.conf`
   - `pkgs.writeShellScript "<name>" (builtins.readFile ../../.local/bin/<name>.sh)`
3. Rebuild.

If you find yourself reaching for `extraConfig = ''…''` or `text = ''…''`,
**stop** — extract the body to one of the directories above instead.

### Add a secret

1. `sops /etc/nixos/mandragora/secrets/secrets.yaml` — opens the file
   decrypted in `$EDITOR`.
2. Add the secret under a sensible YAML key.
3. In `modules/core/secrets.nix`, declare the secret under `sops.secrets`
   with appropriate `path`, `owner`, `mode`.
4. Reference the runtime path elsewhere via
   `config.sops.secrets."<path>".path`.
5. Rebuild.

**Never** open `secrets/secrets.yaml` directly with a text editor — always
via `sops`. Never write a plain-text secret into a `.nix` file.

### Add a service that writes runtime state

1. Define the service module under `modules/<area>/<thing>.nix`.
2. Identify every path the service writes to (typically `/var/lib/<x>`,
   `/etc/<runtime>`, `/var/log/<x>`).
3. **Add each of those paths to `modules/core/impermanence.nix`** under the
   appropriate persistence section. Without this, the state evaporates at
   the next boot.
4. Rebuild.
5. Reboot once and verify the service still has its state — this is the
   only reliable test that impermanence is correctly wired.

### Edit a Hyprland keybind / window rule / animation

The Hyprland config is in `.config/hypr/`:
- `.config/hypr/hyprland.conf` — primary config.
- `.config/hypr/windowrules.conf` — window placement rules.

It's loaded by `modules/desktop/hyprland.nix` via `builtins.readFile`. After
editing, reload Hyprland with `hyprctl reload` (no rebuild needed, since the
config file path is what matters and Hyprland watches it). For changes that
affect the systemd unit or env vars, rebuild.

### Edit zsh aliases / config

zsh aliases live in `snippets/aliases.zsh`. Other zsh config is in
`modules/user/zsh.nix`. The aliases file is read into the module via
`builtins.readFile ../../snippets/aliases.zsh`. After editing, either
`source ~/.zshrc` (if home-manager has placed it there) or rebuild for full
effect.

### Edit waybar

- Config / modules: `.config/waybar/`.
- Style: `snippets/waybar-style.css`.
- Backing scripts (mpd, weather, volume ramp, OBS, screencap):
  `snippets/waybar-*.sh`.

After editing, restart waybar (`pkill waybar` — home-manager-managed user
service will respawn) or rebuild for service-level changes.

### Edit neovim

- All neovim config is under `.config/nvim/`.
- Plugins must be declared via home-manager (no plugin manager that
  bootstraps on first run).

### Add a custom local package

1. Create `pkgs/<name>/default.nix`.
2. Register it in `pkgs/overlays.nix`.
3. Use `pkgs.<name>` in any module.
4. Rebuild.

## Module Hygiene

- **One concern per module.** If a module exceeds one screen, split it.
- **No comments.** Logic is self-documenting through naming and structure.
  Strip existing comments when editing.
- **No imperative shortcuts.** No `pacman`, `chmod`, `systemctl enable` as
  solutions to a runtime issue. Every fix is a Nix expression.

## Multi-Agent File Safety

This codebase is touched by multiple AI agents (Claude, Gemini, local LLMs).
The hard rule:

> **Never rewrite a file from scratch.** Read the current on-disk state
> first, then make targeted edits.

A full rewrite has caused real damage in the past — `home.nix` lost its
`programs.firefox` (with Tridactyl native messaging) on 2026-04-20, making
Firefox unlaunchable until restored from git.

If a full rewrite is unavoidable:
1. Read the file first.
2. Preserve every section you are not explicitly replacing.
3. Log the rewrite in `~/.ai-shared/TASKS.md`.

## Verification

There is no automated test suite. Verification is empirical:

| Scope                | How to verify                                              |
| -------------------- | ---------------------------------------------------------- |
| Configuration evaluates | `sudo nixos-rebuild dry-run --flake /etc/nixos/mandragora#mandragora-desktop` |
| Configuration activates | `sudo nixos-rebuild test --flake /etc/nixos/mandragora#mandragora-desktop` (does not set as boot default) |
| Persistence correctly wired | reboot once after change, verify state survives           |
| State drift detection | run `modules/audits/strays.sh` (or wait for scheduled run) |
| Functional test       | use the feature                                            |

For risky changes (boot, kernel, GPU driver, impermanence list), prefer
`nixos-rebuild test` first — it activates the new config but does not change
the default boot generation, so a reboot rolls back.

## Session Logging

At the end of every session, append to `SESSIONS.md`:

- What was done.
- What broke.
- What friction was encountered.
- What is next.

This is the running log future-you (and future agents) will read to
reconstruct context.

## Related Documents

- `../AGENTS.md` — canonical hard constraints
- `../CLAUDE.md` — Claude Code specifics
- `./project-context.md` — _retired; pointer to AGENTS.md_
- `./architecture.md` — technical architecture
- `./source-tree-analysis.md` — annotated directory layout
- `./deployment-guide.md` — install / reinstall procedure
- `../WORKFLOW.md` — workflow notes
- `../SESSIONS.md` — running session log
- `../FRICTION_LOG.md` — open issues

---

_Generated using BMAD Method `document-project` workflow._
