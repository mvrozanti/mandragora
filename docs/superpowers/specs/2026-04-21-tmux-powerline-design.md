# tmux-powerline on Mandragora

Status bar eye-candy for tmux using the erikw/tmux-powerline plugin (packaged as
`pkgs.tmuxPlugins.tmux-powerline` in nixpkgs).

## Motivation

The current hand-rolled gruvbox status line in `.config/tmux/tmux.conf`
(lines 82-96) uses flat colored blocks without arrow separators or per-window
icons. The user wants proper powerline arrows, Nerd Font glyphs on the window
list, and segment-based left/right chrome — with scope strictly limited to the
window list plus minimal identity info.

## Scope

**In:**
- Arrow-separated left/right segments via tmux-powerline `powerline` theme
- Window list in the centre, each window prefixed with an icon driven by
  `#{pane_current_command}`
- Nix-managed `config.sh` for tmux-powerline living in-repo

**Out (confirmed by user):**
- CPU, load, memory, battery, weather, now-playing, VPN IP, xkb layout,
  earthquake, macOS notifications — all disabled

## Files touched

- `modules/user/tmux.nix` — add plugin; declare `xdg.configFile` for
  `tmux-powerline/config.sh`
- `.config/tmux/tmux.conf` — delete theme block (lines 82-96); replace with
  window-format icons and minimal status wiring that hands chrome to the plugin

## Status bar layout

```
[ session ] ▶  ... ──── centred window list with icons ────  ◀ [vcs] [host] [date] [time]
```

- `status-justify centre`
- Left segments: `tmux_session_info`
- Right segments: `vcs_branch`, `hostname`, `date_day`, `date`, `time`
- Theme: `powerline` (sharp `` `` arrows)

## Window icon mapping

Driven by `#{pane_current_command}` with nested `#{?#{==:...}}` ternaries:

| Command            | Glyph |
|--------------------|-------|
| nvim / vim         |      |
| zsh / bash / fish  |      |
| git                |      |
| ssh                |      |
| btop / htop        |      |
| python             |      |
| node               |      |
| lua                |      |
| (fallback)         |      |

Gruvbox palette carried over via tmux-powerline segment colour overrides in
`config.sh` so the result still harmonises with kitty and Hyprland.

## Font prerequisite

`nerd-fonts.iosevka` is already in `modules/desktop/hyprland.nix:53` and
verified present on the live system via `fc-list`. No font changes required.

## Validation

1. `sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora-desktop`
2. `tmux kill-server && tmux` — fresh session
3. Visual check: arrow separators render, no `?` tofu, segments populated
4. Open `nvim` and `git status` in split panes → confirm window-list icons
   change per pane
5. `tmux display-message -p '#{status-left}#{status-right}'` to inspect the
   resolved format strings

## Non-goals

- No migration tooling; the old theme block is deleted outright
- No per-host variation (desktop vs laptop profile) — same config everywhere
- No tmux-powerline right-segment customisation beyond enable/disable list
