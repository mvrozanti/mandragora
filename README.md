![getting shit done](https://i.imgur.com/NfNMDiW.gif)
![readme](https://i.imgur.com/2EmHLtb.gif)
![stones](https://i.imgur.com/a5ySKOh.gif)
![feeling cute might "hy:%s/<C-r>h//gc<left><left><left> later](https://i.imgur.com/mki87bU.jpg)

# Mandragora

Personal dotfiles and Linux desktop configuration — a tiling WM setup built around **bspwm**, wired together with **sxhkd**, **polybar**, **kitty**, and **neovim**.

## Overview

This is a full desktop environment configuration managed as a dotfiles repository. It covers:

- **Window Manager**: bspwm + sxhkd (keybindings)
- **Terminal**: kitty
- **Editor**: neovim (with plugins via submodules)
- **Bar**: polybar
- **Notifications**: dunst / twmn
- **Music**: mpd + ncmpcpp + cava
- **File Manager**: lf / ranger
- **Shell**: zsh + powerlevel10k + tmux
- **Email**: mutt + mbsync + notmuch
- **Media**: mpv, imv, sxiv, streamlink
- **Compositor**: picom
- **App Launcher**: rofi
- **Display Manager**: ly

## Structure

| Path | Purpose |
|---|---|
| `.*` | Shell-level dotfiles in the home directory root |
| `.config/` | XDG config files (bspwm, polybar, nvim, kitty, etc.) |
| `etc/` | System-level config drops (ly, pacman) |
| `dotty/` | Submodule — dotfile management tool |
| `st/` | Submodule — custom st terminal fork |
| `util/` | Utility submodules |

## Submodules

This repo uses git submodules for plugins and forked tools:

```bash
git submodule update --init --recursive
```

| Submodule | Purpose |
|---|---|
| `dotty` | Dotfile symlink manager |
| `st` / `util/st` | Custom st terminal builds |
| `.config/nvim/plugged/*` | Neovim plugins (Colorizer, LanguageClient, vim-cute-python) |

## Quick Start

1. **Clone** into your home directory:
   ```bash
   git clone <repo-url> ~/mandragora
   ```
2. **Initialize submodules**:
   ```bash
   git submodule update --init --recursive
   ```
3. **Deploy** using your preferred method (stow, symlinks, dotty, etc.)
4. **Start the session**: `~/.start-de` or log in via TTY (autologin.service)

> **Warning**: Deploying dotfiles will overwrite existing configs. Back up your current files first.

## Key Bindings

Defined in `.config/sxhkd/sxhkdrc`. Common patterns:
- `Super + <key>` — window management (focus, move, resize, kill)
- `Super + Shift + <key>` — workspace navigation
- `Super + Return` — launch terminal
- `Super + Space` — launch rofi

## Display / Session

- Session starts via `~/.xinitrc` → `bspwm`
- Auto-login handled via `autologin.service` → `~/.start-de` → `startx`
- Keymap: `us alt-intl` with custom modifications in `~/.Xmodmap`
- DPMS disabled, scroll lock LED repurposed

## Shell

- **Shell**: zsh, configured via `.config/zsh/init.zsh`
- **Prompt**: powerlevel10k (edit `~/.p10k.zsh`)
- **Multiplexer**: tmux (`.tmux.conf`)
- **Aliases**: `.bash_aliases`, `.lf_aliases`
