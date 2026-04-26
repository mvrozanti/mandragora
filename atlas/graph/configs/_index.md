---
type: index
tags: [atlas, index, configs]
---

# Configs

App configuration directories under `/etc/nixos/mandragora/.config/`. Modules pull these in via `builtins.readFile` (per [[../concepts/language-purity|Language Purity]]).

Up: [[../_MOC|Atlas MOC]] · See: [[../modules/_index|Modules]]

## Compositor & display

- [[hypr]] — Hyprland keybinds, monitor layout
- [[wireplumber]] — Pipewire graph (HDMI default)

## Shell & terminal

- [[zsh]] — zshrc, p10k theme
- [[tmux]] — tmux.conf
- [[lf]] — file manager (preview, cleaner, opener)
- [[nvim]] — Neovim editor

## Bars & launchers

- [[waybar]] — status bar (mpd, weather, volume scripts)
- [[eww]] — alternative widget framework
- [[rofi]] — app launcher
- [[quickshell]] — custom shell widgets

## Media

- [[mpd]] — music daemon
- [[ncmpcpp]] — MPD client UI
- [[mpv]] — video player
- [[glava]] — audio visualizer

## Visual / theming

- [[matugen]] — Material You palette generator
- [[flameshot]] — screenshot tool
- [[zathura]] — PDF viewer
- [[nsxiv]] — image viewer
- [[sxiv]] — simple X image viewer

## Input & lighting

- [[keyledsd]] — RGB keyboard config

## Misc

- [[khal]] — CLI calendar
- [[tridactyl]] — Firefox keybindings
- [[claude]] — Claude Code config
- [[crush]] — Crush TUI config
