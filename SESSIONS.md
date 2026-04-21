# Session Log

Running log of what happens each session. Captures decisions, friction, and next steps. Append — do not overwrite.

---

## 2026-04-19 — Session 1: First Light

### Context
System is hours old. Fourth NixOS generation. Hyprland is running (Wayland confirmed). Coming from a 2,790-commit Arch + bspwm + sxhkd setup. User got Claude Code working via a manual `nix shell nixpkgs#nodejs nixpkgs#nix-ld` hack.

### Accomplished
- Full system exploration: architecture, impermanence model, Hyprland stack, BMad framework
- Memory database initialized at `~/.claude/projects/-home-m/memory/`
- **globals.nix**: added `nodejs`, `nix-ld`, `rofi-wayland`, `grim`, `slurp`, `playerctl`, `brightnessctl`, `pamixer`, `mpc-cli`, `jq`
- **impermanence.nix**: fixed `/persistent/home/m` ownership via `systemd.tmpfiles.rules`; added `.local/share/mpd` and `projects/` to persistence
- **home.nix**: full Hyprland user config:
  - Keyboard: `us-intl` layout with dead keys (apostrophe+c → ç)
  - Key repeat: 200ms delay, 30 repeats/sec
  - Smart launch (`Super+digit` focuses existing window or launches app)
  - All sxhkd keybindings translated to Hyprland
  - mpd + ncmpcpp via home-manager user services
  - Window rules: apps auto-assigned to workspaces
- `snippets/smart-launch.sh`: focus-or-launch script using `hyprctl` + `jq`
- `snippets/mpd.conf`: PipeWire audio output config
- `CLAUDE.md`: comprehensive AI agent guide for this repo
- `SESSIONS.md`: this file

### Friction / Hardships
- `/etc/nixos/` files were root-owned → Edit tool blocked; needed sudo context to write
- `nodejs` not in system config → had to use `nix shell` hack to get claude-code working at all
- `/persistent/home/m` was root-owned → home appeared root-owned after reboot; fixed declaratively via tmpfiles
- No keybindings configured → Hyprland defaults only; couldn't navigate efficiently
- sxhkd muscle memory doesn't translate to Hyprland — requires explicit config
- Old bspwm had `Super+1-5` as app launchers (not workspace switchers) — kept this convention

### Security Layer Added (same session)
- `modules/core/security.nix`: firewall (explicit), DNS-over-TLS (Cloudflare + Quad9), sudo hardening (10min timeout, logging), kernel sysctl hardening, sshd disabled but hardened config ready
- `snippets/sudo.conf`, `snippets/resolved.conf`: externalized config strings per language purity rule
- `programs.hyprlock` + `services.hypridle`: screen lock after 5min idle, display off after 10min
- `Super+Home` → hyprlock, `Super+BackSpace` → display off (matches old sxhkd)
- `hosts/mandragora-desktop/default.nix`: imports security.nix
- Old mandragora repo cloned to `~/projects/mandragora`
- CLAUDE.md documented: SSH key import process, full disk encryption gap

### NOT YET DONE (Next Session)
- [ ] Run `sudo nixos-rebuild switch --flake /etc/nixos/mandragora-nixos#mandragora-desktop` and fix any errors
- [ ] Verify keybindings work in live session
- [ ] Verify music plays (mpd → ncmpcpp → PipeWire)
- [ ] Clone old mandragora repo to `~/projects/mandragora`
- [ ] Migrate zsh config (powerlevel10k, aliases, functions)
- [ ] Migrate tmux config
- [ ] Migrate neovim config
- [ ] Set up Waybar CSS styling (currently unstyled)
- [ ] Implement `mandragora-switch` alias (git sync + rebuild)
- [ ] Verify `us-intl` dead keys work (apostrophe+c = ç)
- [ ] Commit and push all these changes to GitHub
- [ ] Import SSH/GPG keys into sops vault (user needs to locate key material — Ventoy USB or old machine)
- [ ] Full disk encryption (dedicated session with Ventoy USB — major operation)
- [ ] Locate old SSH/GPG keys (Ventoy USB needs mounting: `sudo mount -o ro /dev/sda1 /mnt`) and import into sops
- [ ] Full disk encryption (dedicated session with Ventoy USB)
- [ ] Ollama: pull a model after rebuild (`ollama pull qwen2.5-coder:14b` or `ollama pull gemma3:27b`)
- [ ] Configure MCP server for Ollama → Claude Code integration
- [ ] Fuse mandragora and mandragora-nixos repos (long-term, post-migration)

## Session: 2026-04-19 — Core Migration & Syntax Stabilization
**Status:** Success (after stabilization)
**Work Done:**
- **Core Migration:** Successfully migrated `zsh`, `tmux`, `kitty`, and `lf` from legacy dotfiles to Nix/Home Manager.
- **Language Purity Refactor:** Moved all non-Nix configuration blocks (Hyprland, Zsh, Tmux) into `snippets/` and referenced them via `builtins.readFile`.
- **Hyprland 0.54.3 Stabilization:** Resolved multiple configuration errors by migrating to the modern "Named Rule Block" syntax for window rules and fixing the `decoration:shadow` syntax.
- **Environment Fixes:** Restored global font scaling (DPI) and cedilla/accent support via `XCompose` and explicit `IM_MODULE` environment variables.
- **Planning:** Added Phase 7 to `EXECUTION_PLAN.md` for the systematic migration of 56 scripts in `~/.local/bin/`.

**What Broke:**
- **Stale Configs:** Home Manager was blocked by a stale `hyprland.conf` symlink; required manual removal (`rm -f`).
- **Syntax Shifts:** Attempted multiple deprecated `windowrule` syntaxes before finding the stable block-style format for version 0.54.3.
- **Font Mismatch:** `IosevkaTerm` vs `Iosevka` font names caused massive font fallback issues.

**Next Steps:**
- Execute Phase 7: Categorize and "Nixify" the 56 scripts in `~/projects/mandragora/.local/bin/`.
- Group 1 to migrate: UI/Window Management utilities (`center-window.sh`, `blur-strength`, etc.).

---

## Session 2026-04-20

### Done
- Implemented `biggest-pane` script (hyprctl-based replacement for `bspc node -f biggest.local`); wired to `SUPER+Return` in hyprland.conf
- Confirmed local LLM (Ollama+CUDA) already working via `ai-local.nix`
- Committed and pushed all Phase A+B work (GUI apps, ncmpcpp, zathura, mpv, rofi) to GitHub
- Waybar CSS: aligned to One Dark palette (#282c34 bg, full rofi color set for module underlines); added workspace 18 (TradingView) icon
- Ported tridactyl `hints.css`; added `home.file` link for `.config/tridactyl`
- Removed `ranger` from packages (using `lf` instead)
- Saved feedback memory: autonomous work mode — no stopping between tasks

### What broke
- Nothing

### Next
- Task #6: Import SSH/GPG keys into sops vault
- Task #15: Firefox Sync re-login
- Audit remaining `.config/` dirs in old dotfiles not yet ported (khal, mutt, cava)

---

## Session 2026-04-20 (continued)

### Done
- **keyledsd lightning**: Confirmed custom `lightning.lua` is injected into the running derivation and loading cleanly (no errors since 18:05). Effect is active.
- **lf fixes**: nsxiv→sxiv, ueberzug→ueberzugpp, nixified path references in lf.nix, zshrc, aliases.zsh
- **cava config**: Ported from old dotfiles with 120fps, custom One Dark-ish gradient
- **khal config**: Ported with local calendar path and date format preferences
- **mako styling**: One Dark palette (bg #282c34, text #abb2bf, border #61afef)
- **sxiv key-handler**: Ported and Wayland-ified (xsel→wl-copy)
- **hyprlock**: Set up with One Dark clock+input field, 5-min idle lock
- **hypridle**: 5min→lock, 10min→display off

### What broke
- Nothing

### Next
- Task #6: Import SSH/GPG keys into sops vault (requires locating key material on Ventoy USB)
- Task #15: Firefox Sync re-login (UI task, user does manually)
- mutt/neomutt: complex OAuth2 setup, defer until needed
- Seafile: needs server URL + auth token before enabling
