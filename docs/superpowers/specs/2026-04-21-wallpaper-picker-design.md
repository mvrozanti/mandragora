# Wallpaper Picker + matugen — Design Spec

**Date**: 2026-04-21  
**Status**: Approved

---

## Overview

Replace the existing `SUPER+G` → `setbg` (random wallpaper) binding with a QuickShell-based wallpaper picker ported from [ilyamiro/nixos-configuration](https://github.com/ilyamiro/nixos-configuration). The picker provides a local thumbnail grid and DuckDuckGo online search. Simultaneously migrate from pywal to matugen for color scheme generation.

---

## Architecture

SUPER+G launches a standalone `quickshell` process. It creates a fullscreen WlrLayershell Overlay window containing the WallpaperPicker widget (1920×650px, vertically centered). The process is **not** a persistent daemon — it exits after a wallpaper is picked or ESC is pressed.

When the user selects a wallpaper, the picker:
1. Writes `close` to `/tmp/qs_widget_state` (causes QuickShell to exit)
2. Runs `awww img` for the animated wallpaper transition (detached/disowned)
3. Runs `matugen image <thumb>` to generate color scheme (detached)
4. Calls `matugen_reload.sh` to propagate colors to all apps

---

## New Files

### `.config/quickshell/`

| File | Source |
|------|--------|
| `Main.qml` | Custom minimal launcher (see below) |
| `MatugenColors.qml` | Verbatim from reference repo |
| `Scaler.qml` | Verbatim from reference repo |
| `WindowRegistry.js` | Verbatim from reference repo |
| `wallpaper/WallpaperPicker.qml` | From reference, one adaptation: `swww img` → `awww img` |
| `wallpaper/ddg_search.sh` | Verbatim from reference repo |
| `wallpaper/get_ddg_links.py` | Verbatim from reference repo |
| `wallpaper/matugen_reload.sh` | Custom for this system (see below) |

#### Main.qml design

```qml
PanelWindow (WlrLayer.Overlay, focusable, transparent background)
  MouseArea (full screen, click-to-dismiss → Qt.quit())
  Keys.onEscapePressed → Qt.quit()
  Item (x:0, y:(Screen.height-650)/2, width:Screen.width, height:650)
    WallpaperPicker { anchors.fill: parent }
  Process (inotifywait /tmp/qs_widget_state, on "close" → Qt.quit())
```

The Process clears `/tmp/qs_widget_state` on startup to avoid stale signals.

#### matugen_reload.sh design

Runs after `matugen image` completes. Inherits `$WALL_FILE` env from picker's apply script.

1. Write `$WALL_FILE` to `~/.cache/matugen/last-wallpaper` (for restore-theme)
2. `killall -USR1 .kitty-wrapped` — live-reload kitty colors
3. `pkill -SIGUSR2 waybar` — reload waybar
4. `makoctl reload` — reload mako notification daemon
5. `keyledsd-reload` — reload keyboard LED colors
6. GTK live-reload hack (toggle theme via gsettings to flush CSS cache)

### `.config/matugen/`

| File | Source | Output path |
|------|--------|-------------|
| `config.toml` | Custom | — |
| `templates/colors.json.template` | Verbatim from reference | `/tmp/qs_colors.json` |
| `templates/kitty-colors.conf.template` | Verbatim from reference | `~/.cache/matugen/colors-kitty.conf` |
| `templates/rofi.rasi.template` | Verbatim from reference | `~/.cache/matugen/colors-rofi.rasi` |

`config.toml` sets `reload_apps = false` (apps are reloaded manually via the reload script).

---

## Modified Files

### `modules/user/home.nix`

- **Add packages**: `quickshell`, `matugen`
- **Remove package**: `pywal`
- **Remove script**: `wal-to-rgb` writeShellScriptBin
- **Kitty**: change `extraConfig` from `include ~/.cache/wal/colors-kitty.conf` → `include ~/.cache/matugen/colors-kitty.conf`
- **Remove home.file entries**: `.config/wal/templates/keyledsd.conf`, `.config/wal/templates/colors-rofi.rasi`
- **Add home.file entries**:
  - `.config/quickshell` → recursive source from `../../.config/quickshell`
  - `.config/matugen` → recursive source from `../../.config/matugen`

### `.local/bin/setbg.sh`

Used by: `restore-theme.sh` (login) and `rofi-wallpaper-picker` (ALT+SUPER+G).

Changes:
- Replace `wal -i "$fpath" -n -q` with `matugen image "$fpath"`
- Write `$fpath` to `~/.cache/matugen/last-wallpaper`
- Remove `wal-to-rgb &` call
- Inline app reloads: kitty USR1, waybar SIGUSR2, mako reload, keyledsd-reload, hyprctl reload

### `.local/bin/restore-theme.sh`

Changes:
- Read from `~/.cache/matugen/last-wallpaper` instead of `~/.cache/wal/wal`
- Fall back to `setbg` (random pick) if file missing

### `.config/hypr/hyprland.conf` (line 190)

```
# Before
bind = $mainMod, G, exec, setbg

# After
bind = $mainMod, G, exec, quickshell
```

---

## Wallpaper Directory

WallpaperPicker reads `$WALLPAPER_DIR` env var. This is already set in `home.nix`:
```nix
WALLPAPER_DIR = "${config.home.homeDirectory}/Pictures/wllpps";
```
No change needed.

---

## Dependencies (all already installed)

- `imagemagick` — webp conversion in ddg_search.sh
- `inotify-tools` — file watching in Main.qml IPC
- `curl` — DDG thumbnail downloads
- `python3` — get_ddg_links.py scraper
- `awww` — wallpaper daemon (already in use)

---

## Out of Scope

- Replacing waybar with the full QuickShell shell from the reference repo
- matugen templates for GTK, Qt, nvim, discord — can be added later
- pywal rofi color template (`.config/wal/templates/colors-rofi.rasi`) — replaced by matugen rofi template; old wal template file deleted

---

## Testing

1. `nixos-rebuild switch` succeeds
2. SUPER+G opens QuickShell picker (fullscreen overlay, grid visible)
3. Local wallpapers populate from `~/Pictures/wllpps`
4. Clicking a wallpaper: transition plays, colors update in kitty/waybar/rofi
5. `~/.cache/matugen/last-wallpaper` is written
6. ESC dismisses without changing wallpaper
7. DDG search tab finds and downloads images
8. Logout/login: `restore-theme` applies last wallpaper and matugen colors
9. ALT+SUPER+G rofi picker still works (calls `setbg`, which now uses matugen)
