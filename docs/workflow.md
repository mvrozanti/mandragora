# Workflow — Edit, Rebuild, Verify, Commit

## Prerequisites

- The Mandragora workstation already running NixOS with this configuration.
  (For a fresh install, see [`install/INSTALL.md`](install/INSTALL.md).)
- Sudo access to run `nixos-rebuild switch`.
- Age private key at `/persistent/secrets/keys.txt` (auto-imported during
  install; see `docs/install/bootstrap-age-key.sh`).
- `git`, `nix` with `flakes` and `nix-command` features enabled (already on
  via `nix/modules/core/globals.nix`).

## Repository locations

The same git working tree is reachable at two paths:

| Path | Purpose |
|------|---------|
| `/etc/nixos/mandragora/` | Canonical path consumed by `nixos-rebuild --flake` |
| `/persistent/mandragora/` | Bind-mounted alias; convenient when working from `/persistent` |

Both point at the exact same files. Edit anywhere; commit anywhere.

Owner: `m:users`. No sudo is required to edit files. Sudo *is* required to
rebuild.

Remote: `https://github.com/mvrozanti/mandragora.git`.

## The loop

```
1. Edit    /etc/nixos/mandragora/<file>
2. Rebuild + Commit + Push: mandragora-switch [optional commit message]
3. Verify  test the changed feature directly
```

`mandragora-switch` (defined in `.local/bin/mandragora-switch.sh`, exposed
via `nix/modules/user/home.nix`) does, in order: `git fetch` → rebase if
behind → `git add -A` → open staged-diff editor for commit message (skip
with `!`) → `sudo nixos-rebuild switch` → `git push`.

Aliases (in `nix/modules/user/zsh.nix`):

| Alias | Behavior |
|-------|----------|
| `nrc` | `mandragora-switch` (full cycle with commit-message editor) |
| `nrs` | `mandragora-switch !` (skip diff editor, no commit) |
| `nrp` | `mandragora-commit-push` (commit + push only, no rebuild — used when only docs/markdown changed) |
| `nrb` | rebuild boot |
| `nrt` | rebuild test |

If `mandragora-switch` is unavailable (e.g., during initial install or
recovery), the manual equivalent is:

```bash
sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora-desktop \
  && cd /etc/nixos/mandragora && git add -A && git commit && git push
```

### Why "commit before reboot"

`/etc/nixos/` does **not** survive impermanence wipes — only the git remote
is the persistence mechanism for the configuration source. **Always commit
and push before rebooting.** A commit that exists only in a working tree
under `/etc/nixos/` will be gone after the next boot if it has not been
pushed to the persistent path or to the remote.

(The bind-mount from `/persistent/mandragora/` to `/etc/nixos/mandragora/`
means files actually live under `/persistent`, so they *do* survive
reboot on disk. But the discipline of "commit before reboot" remains: it
ensures remote backup and protects against accidental wipes of the
persistent subvolume.)

## Common tasks

### Add a system-wide package

1. Open `nix/modules/core/globals.nix`.
2. Add the package name to `environment.systemPackages`.
3. Rebuild.

For an ephemeral try-before-you-commit:

```bash
nix shell nixpkgs#<package>
```

This is closed when the shell exits. **Always** follow up by adding the
package to `globals.nix` for permanence.

### Add a user-only package

1. Open `nix/modules/user/home.nix`.
2. Add the package to `home.packages`.
3. Rebuild.

### Add a new module

1. Create `nix/modules/<area>/<thing>.nix` — pick the closest area
   (`core`/`desktop`/`user`/`audits`).
2. Keep it focused on one concern; aim for ≤ one screen of code.
3. Add the import line to `nix/hosts/mandragora-desktop/default.nix`.
4. Rebuild.

### Add a non-Nix file (shell script, config, lua, css)

The "language purity" rule forbids embedding non-Nix bodies inside `.nix`
files. Instead:

1. Place the file in its XDG-mirrored location at the repo root:
   - Shell script that you'd call from a keybind: `.local/bin/<name>.sh`.
   - App config: `.config/<app>/<file>.conf`.
   - Helper called by another script or `programs.*`: `nix/snippets/<name>.<ext>`.
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
3. In `nix/modules/core/secrets.nix`, declare the secret under `sops.secrets`
   with appropriate `path`, `owner`, `mode`.
4. Reference the runtime path elsewhere via
   `config.sops.secrets."<path>".path`.
5. Rebuild.

**Never** open `secrets/secrets.yaml` directly with a text editor — always
via `sops`. Never write a plain-text secret into a `.nix` file. See
[`secrets.md`](./secrets.md) for the full secrets contract.

### Add a service that writes runtime state

1. Define the service module under `nix/modules/<area>/<thing>.nix`.
2. Identify every path the service writes to (typically `/var/lib/<x>`,
   `/etc/<runtime>`, `/var/log/<x>`).
3. **Add each of those paths to `nix/modules/core/impermanence.nix`** under the
   appropriate persistence section. Without this, the state evaporates at
   the next boot.
4. Rebuild.
5. Reboot once and verify the service still has its state — this is the
   only reliable test that impermanence is correctly wired.

### Edit a Hyprland keybind / window rule / animation

The Hyprland config is in `.config/hypr/`:
- `.config/hypr/hyprland.conf` — primary config.
- `.config/hypr/windowrules.conf` — window placement rules.

It's loaded by `nix/modules/desktop/hyprland.nix` via `builtins.readFile`.
After editing, reload Hyprland with `hyprctl reload` (no rebuild needed,
since the config file path is what matters and Hyprland watches it). For
changes that affect the systemd unit or env vars, rebuild.

After every edit, run `hyprctl configerrors` and confirm empty output —
Hyprland silently drops unknown fields and keeps running, so a successful
reload does not imply a valid config.

### Edit zsh aliases / config

zsh aliases live in `nix/snippets/aliases.zsh`. Other zsh config is in
`nix/modules/user/zsh.nix`. The aliases file is read into the module via
`builtins.readFile ../../nix/snippets/aliases.zsh`. After editing, either
`source ~/.zshrc` or rebuild for full effect.

### Edit waybar

- Config / modules: `.config/waybar/`.
- Style: `nix/snippets/waybar-style.css`.
- Backing scripts (mpd, weather, volume ramp, OBS, screencap):
  `nix/snippets/waybar-*.sh`.

After editing, restart waybar (`pkill waybar` — home-manager-managed user
service will respawn) or rebuild for service-level changes.

### Edit neovim

- All neovim config is under `.config/nvim/`.
- Plugins must be declared via home-manager (no plugin manager that
  bootstraps on first run).

### Add a custom local package

1. Create `nix/pkgs/<name>/default.nix`.
2. Register it in `nix/pkgs/overlays.nix`.
3. Use `pkgs.<name>` in any module.
4. Rebuild.

## Module hygiene

- **One concern per module.** If a module exceeds one screen, split it.
- **No comments.** Logic is self-documenting through naming and structure.
  Strip existing comments when editing.
- **No imperative shortcuts.** No `pacman`, `chmod`, `systemctl enable` as
  solutions to a runtime issue. Every fix is a Nix expression.

## Verification

There is no automated test suite. Verification is empirical:

| Scope | How to verify |
|-------|---------------|
| Configuration evaluates | `sudo nixos-rebuild dry-run --flake /etc/nixos/mandragora#mandragora-desktop` |
| Configuration activates | `sudo nixos-rebuild test --flake /etc/nixos/mandragora#mandragora-desktop` (does not set as boot default) |
| Persistence correctly wired | reboot once after change, verify state survives |
| State drift detection | run `nix/modules/audits/strays.sh` (or wait for scheduled run) |
| Functional test | use the feature |

For risky changes (boot, kernel, GPU driver, impermanence list), prefer
`nixos-rebuild test` first — it activates the new config but does not
change the default boot generation, so a reboot rolls back.

After every `.nix` edit, run `nix-instantiate --parse <file> >/dev/null`
(AGENTS.md Rule 11). After every `.config/hypr/*.conf` edit or
`hyprctl reload`, run `hyprctl configerrors`.
