# Wallpaper Picker + matugen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the QuickShell-based wallpaper picker from ilyamiro/nixos-configuration and migrate from pywal to matugen for color scheme generation.

**Architecture:** A standalone `quickshell` process launched on SUPER+G shows a fullscreen overlay picker (local grid + DDG search). Picking a wallpaper runs `awww img` + `matugen image` (detached), then calls `matugen_reload.sh` to propagate colors to kitty/waybar/mako/keyledsd. The process exits after picking. No daemon.

**Tech Stack:** QuickShell 0.2.1 (QML), matugen 4.0.0, awww (swww-compatible wallpaper daemon), bash, Python 3

**Reference repo:** https://github.com/ilyamiro/nixos-configuration

---

## File Map

| Action | Path |
|--------|------|
| Create | `.config/quickshell/Main.qml` |
| Create | `.config/quickshell/MatugenColors.qml` |
| Create | `.config/quickshell/Scaler.qml` |
| Create | `.config/quickshell/WindowRegistry.js` |
| Create | `.config/quickshell/wallpaper/WallpaperPicker.qml` |
| Create | `.config/quickshell/wallpaper/ddg_search.sh` |
| Create | `.config/quickshell/wallpaper/get_ddg_links.py` |
| Create | `.config/quickshell/wallpaper/matugen_reload.sh` |
| Create | `.config/matugen/config.toml` |
| Create | `.config/matugen/templates/colors.json.template` |
| Create | `.config/matugen/templates/kitty-colors.conf.template` |
| Create | `.config/matugen/templates/rofi.rasi.template` |
| Modify | `.local/bin/setbg.sh` |
| Modify | `.local/bin/restore-theme.sh` |
| Modify | `.config/rofi/theme.rasi` |
| Modify | `modules/user/home.nix` |
| Modify | `.config/hypr/hyprland.conf` |

All paths are relative to `/etc/nixos/mandragora/`.

---

### Task 1: QuickShell — fetch verbatim supporting files

**Files:**
- Create: `.config/quickshell/MatugenColors.qml`
- Create: `.config/quickshell/Scaler.qml`
- Create: `.config/quickshell/WindowRegistry.js`

- [ ] **Step 1: Create quickshell directory and fetch files from reference repo**

```bash
cd /etc/nixos/mandragora
mkdir -p .config/quickshell/wallpaper

gh api 'repos/ilyamiro/nixos-configuration/contents/config/sessions/hyprland/scripts/quickshell/MatugenColors.qml' \
  --jq '.content' | base64 -d > .config/quickshell/MatugenColors.qml

gh api 'repos/ilyamiro/nixos-configuration/contents/config/sessions/hyprland/scripts/quickshell/Scaler.qml' \
  --jq '.content' | base64 -d > .config/quickshell/Scaler.qml

gh api 'repos/ilyamiro/nixos-configuration/contents/config/sessions/hyprland/scripts/quickshell/WindowRegistry.js' \
  --jq '.content' | base64 -d > .config/quickshell/WindowRegistry.js
```

- [ ] **Step 2: Verify files are non-empty**

```bash
wc -l /etc/nixos/mandragora/.config/quickshell/MatugenColors.qml \
       /etc/nixos/mandragora/.config/quickshell/Scaler.qml \
       /etc/nixos/mandragora/.config/quickshell/WindowRegistry.js
```

Expected: MatugenColors ~60 lines, Scaler ~55 lines, WindowRegistry ~65 lines.

- [ ] **Step 3: Commit**

```bash
cd /etc/nixos/mandragora
git add .config/quickshell/
git commit -m "feat: add quickshell MatugenColors, Scaler, WindowRegistry"
```

---

### Task 2: QuickShell — fetch and adapt WallpaperPicker.qml

**Files:**
- Create: `.config/quickshell/wallpaper/WallpaperPicker.qml`

The reference repo uses `swww img` but our system uses `awww img`. This task fetches the file and applies the substitution.

- [ ] **Step 1: Fetch WallpaperPicker.qml and patch swww → awww**

```bash
cd /etc/nixos/mandragora
gh api 'repos/ilyamiro/nixos-configuration/contents/config/sessions/hyprland/scripts/quickshell/wallpaper/WallpaperPicker.qml' \
  --jq '.content' | base64 -d > .config/quickshell/wallpaper/WallpaperPicker.qml

sed -i 's/swww img/awww img/g' .config/quickshell/wallpaper/WallpaperPicker.qml
```

- [ ] **Step 2: Verify the substitution — no remaining `swww img` references**

```bash
grep -n "swww img" /etc/nixos/mandragora/.config/quickshell/wallpaper/WallpaperPicker.qml
```

Expected: no output (zero matches).

- [ ] **Step 3: Verify awww-daemon reference is present (already correct in source)**

```bash
grep -n "awww-daemon\|awww img" /etc/nixos/mandragora/.config/quickshell/wallpaper/WallpaperPicker.qml | head -10
```

Expected: multiple `awww img` lines and at least one `awww-daemon` line.

- [ ] **Step 4: Commit**

```bash
cd /etc/nixos/mandragora
git add .config/quickshell/wallpaper/WallpaperPicker.qml
git commit -m "feat: add WallpaperPicker.qml (awww img adaptation)"
```

---

### Task 3: QuickShell — DDG search scripts

**Files:**
- Create: `.config/quickshell/wallpaper/ddg_search.sh`
- Create: `.config/quickshell/wallpaper/get_ddg_links.py`

- [ ] **Step 1: Fetch scripts**

```bash
cd /etc/nixos/mandragora

gh api 'repos/ilyamiro/nixos-configuration/contents/config/sessions/hyprland/scripts/quickshell/wallpaper/ddg_search.sh' \
  --jq '.content' | base64 -d > .config/quickshell/wallpaper/ddg_search.sh

gh api 'repos/ilyamiro/nixos-configuration/contents/config/sessions/hyprland/scripts/quickshell/wallpaper/get_ddg_links.py' \
  --jq '.content' | base64 -d > .config/quickshell/wallpaper/get_ddg_links.py

chmod +x .config/quickshell/wallpaper/ddg_search.sh
chmod +x .config/quickshell/wallpaper/get_ddg_links.py
```

- [ ] **Step 2: Verify files are non-empty and executable**

```bash
ls -la /etc/nixos/mandragora/.config/quickshell/wallpaper/
```

Expected: `ddg_search.sh` and `get_ddg_links.py` both show `-rwxr-xr-x`.

- [ ] **Step 3: Commit**

```bash
cd /etc/nixos/mandragora
git add .config/quickshell/wallpaper/ddg_search.sh \
        .config/quickshell/wallpaper/get_ddg_links.py
git commit -m "feat: add DDG wallpaper search scripts"
```

---

### Task 4: QuickShell — write matugen_reload.sh

**Files:**
- Create: `.config/quickshell/wallpaper/matugen_reload.sh`

This script runs after `matugen image` completes. It inherits `$WALL_FILE` from the picker's apply script env.

- [ ] **Step 1: Write matugen_reload.sh**

```bash
cat > /etc/nixos/mandragora/.config/quickshell/wallpaper/matugen_reload.sh << 'EOF'
#!/usr/bin/env bash

# Persist last wallpaper path for restore-theme (WALL_FILE is exported by the picker)
if [[ -n "${WALL_FILE:-}" ]]; then
    mkdir -p ~/.cache/matugen
    echo "$WALL_FILE" > ~/.cache/matugen/last-wallpaper
fi

# Reload Kitty color scheme live
killall -USR1 .kitty-wrapped 2>/dev/null || true

# Reload waybar
pkill -SIGUSR2 waybar 2>/dev/null || true

# Reload mako notification daemon
makoctl reload 2>/dev/null || true

# Reload keyboard LED colors
keyledsd-reload 2>/dev/null || true

# GTK live-reload: rapidly toggle theme to flush GTK3/GTK4 CSS caches
if command -v gsettings &>/dev/null; then
    gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita'
    sleep 0.05
    gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
    gsettings set org.gnome.desktop.interface color-scheme 'default'
    sleep 0.05
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
fi
EOF
chmod +x /etc/nixos/mandragora/.config/quickshell/wallpaper/matugen_reload.sh
```

- [ ] **Step 2: Verify it's executable and syntactically valid**

```bash
bash -n /etc/nixos/mandragora/.config/quickshell/wallpaper/matugen_reload.sh && echo "OK"
```

Expected: `OK`

- [ ] **Step 3: Commit**

```bash
cd /etc/nixos/mandragora
git add .config/quickshell/wallpaper/matugen_reload.sh
git commit -m "feat: add matugen_reload.sh for our setup"
```

---

### Task 5: QuickShell — write Main.qml

**Files:**
- Create: `.config/quickshell/Main.qml`

Standalone launcher: fullscreen Overlay window, WallpaperPicker centered at 650px height, exits on close signal or ESC.

- [ ] **Step 1: Write Main.qml**

```bash
cat > /etc/nixos/mandragora/.config/quickshell/Main.qml << 'EOF'
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "wallpaper"

PanelWindow {
    id: root
    color: "transparent"

    WlrLayershell.namespace: "qs-wallpaper-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    focusable: true

    width: Screen.width
    height: Screen.height

    // Scale matches WindowRegistry.js wallpaper layout: h: s(650, scale)
    readonly property real pickerScale: {
        let r = Screen.width / 1920.0
        return r <= 1.0 ? Math.max(0.35, Math.pow(r, 0.85)) : Math.pow(r, 0.5)
    }
    readonly property int pickerHeight: Math.round(650 * pickerScale)

    Keys.onEscapePressed: Qt.quit()

    MouseArea {
        anchors.fill: parent
        onClicked: Qt.quit()
    }

    Item {
        x: 0
        y: Math.floor((Screen.height - root.pickerHeight) / 2)
        width: Screen.width
        height: root.pickerHeight

        WallpaperPicker {
            width: parent.width
            height: parent.height
        }
    }

    // Watch for "close" written by picker after wallpaper apply
    Process {
        id: ipcWatcher
        command: ["bash", "-c",
            "echo '' > /tmp/qs_widget_state; " +
            "touch /tmp/qs_widget_state; " +
            "inotifywait -qq -e close_write /tmp/qs_widget_state 2>/dev/null; " +
            "cat /tmp/qs_widget_state"
        ]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "close") Qt.quit()
            }
        }
    }
}
EOF
```

- [ ] **Step 2: Check for syntax issues (basic sanity — QML can't be shell-validated)**

```bash
grep -c "import\|PanelWindow\|WallpaperPicker\|Qt.quit" /etc/nixos/mandragora/.config/quickshell/Main.qml
```

Expected: 7 (or more, one per occurrence)

- [ ] **Step 3: Commit**

```bash
cd /etc/nixos/mandragora
git add .config/quickshell/Main.qml
git commit -m "feat: add standalone QuickShell Main.qml"
```

---

### Task 6: matugen — config and templates

**Files:**
- Create: `.config/matugen/config.toml`
- Create: `.config/matugen/templates/colors.json.template`
- Create: `.config/matugen/templates/kitty-colors.conf.template`
- Create: `.config/matugen/templates/rofi.rasi.template`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p /etc/nixos/mandragora/.config/matugen/templates
```

- [ ] **Step 2: Write config.toml**

```bash
cat > /etc/nixos/mandragora/.config/matugen/config.toml << 'EOF'
[config]
reload_apps = false

[templates.quickshell]
input_path = "~/.config/matugen/templates/colors.json.template"
output_path = "/tmp/qs_colors.json"

[templates.kitty]
input_path = "~/.config/matugen/templates/kitty-colors.conf.template"
output_path = "~/.cache/matugen/colors-kitty.conf"

[templates.rofi]
input_path = "~/.config/matugen/templates/rofi.rasi.template"
output_path = "~/.cache/matugen/colors-rofi.rasi"
EOF
```

- [ ] **Step 3: Fetch colors.json.template from reference repo**

```bash
gh api 'repos/ilyamiro/nixos-configuration/contents/config/sessions/hyprland/scripts/quickshell/colors.json.template' \
  --jq '.content' | base64 -d > /etc/nixos/mandragora/.config/matugen/templates/colors.json.template
```

- [ ] **Step 4: Fetch kitty-colors.conf.template from reference repo**

```bash
gh api 'repos/ilyamiro/nixos-configuration/contents/config/programs/matugen/templates/kitty-colors.conf.template' \
  --jq '.content' | base64 -d > /etc/nixos/mandragora/.config/matugen/templates/kitty-colors.conf.template
```

- [ ] **Step 5: Fetch rofi.rasi.template from reference repo**

```bash
gh api 'repos/ilyamiro/nixos-configuration/contents/config/programs/matugen/templates/rofi.rasi.template' \
  --jq '.content' | base64 -d > /etc/nixos/mandragora/.config/matugen/templates/rofi.rasi.template
```

- [ ] **Step 6: Verify all four files exist and are non-empty**

```bash
wc -l /etc/nixos/mandragora/.config/matugen/config.toml \
       /etc/nixos/mandragora/.config/matugen/templates/colors.json.template \
       /etc/nixos/mandragora/.config/matugen/templates/kitty-colors.conf.template \
       /etc/nixos/mandragora/.config/matugen/templates/rofi.rasi.template
```

Expected: config.toml ~18 lines, colors.json.template ~25 lines, kitty-colors ~55 lines, rofi.rasi ~30+ lines.

- [ ] **Step 7: Commit**

```bash
cd /etc/nixos/mandragora
git add .config/matugen/
git commit -m "feat: add matugen config and templates (kitty, rofi, quickshell colors)"
```

---

### Task 7: Update setbg.sh — replace pywal with matugen

**Files:**
- Modify: `.local/bin/setbg.sh`

`setbg.sh` is used by `restore-theme` at login and by the `rofi-wallpaper-picker` script.

- [ ] **Step 1: Overwrite setbg.sh with matugen-based version**

```bash
cat > /etc/nixos/mandragora/.local/bin/setbg.sh << 'EOF'
#!/usr/bin/env bash
set -u

dir="${WALLPAPER_DIR:-$HOME/Pictures/wllpps}"
fpath="${1:-}"
if [[ -z "$fpath" ]]; then
    fpath="$(find "$dir" -maxdepth 2 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
           -o -iname '*.gif' -o -iname '*.webp' \) 2>/dev/null | shuf | head -1)"
fi
if [[ -z "$fpath" || ! -e "$fpath" ]]; then
    notify-send -u critical "setbg" "No wallpaper found in $dir" 2>/dev/null || true
    echo "setbg: no wallpaper found in $dir" >&2
    exit 1
fi
fpath="$(realpath "$fpath")"

pos="$(hyprctl cursorpos 2>/dev/null | tr -d ' ' || true)"
pos="${pos:-960,540}"
awww img "$fpath" \
    --transition-type grow \
    --transition-pos "$pos" \
    --transition-duration 1

mkdir -p ~/.cache/matugen
echo "$fpath" > ~/.cache/matugen/last-wallpaper

matugen image "$fpath"

killall -USR1 .kitty-wrapped 2>/dev/null || true
pkill -SIGUSR2 waybar 2>/dev/null || true
makoctl reload 2>/dev/null || true
hid-wrapper &
keyledsd-reload &
hyprctl reload 2>/dev/null || true
wait

notify-send -t 2500 "Theme" "$(basename "$fpath")" 2>/dev/null || true
EOF
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n /etc/nixos/mandragora/.local/bin/setbg.sh && echo "OK"
```

Expected: `OK`

- [ ] **Step 3: Confirm no wal references remain**

```bash
grep "wal\b" /etc/nixos/mandragora/.local/bin/setbg.sh
```

Expected: no output.

- [ ] **Step 4: Commit**

```bash
cd /etc/nixos/mandragora
git add .local/bin/setbg.sh
git commit -m "feat: replace pywal with matugen in setbg.sh"
```

---

### Task 8: Update restore-theme.sh — read matugen cache

**Files:**
- Modify: `.local/bin/restore-theme.sh`

- [ ] **Step 1: Overwrite restore-theme.sh**

```bash
cat > /etc/nixos/mandragora/.local/bin/restore-theme.sh << 'EOF'
#!/usr/bin/env bash
# Re-apply the last wallpaper on login, once awww-daemon is up.
set -u

for _ in $(seq 1 20); do
    awww query >/dev/null 2>&1 && break
    sleep 0.25
done

last="$HOME/.cache/matugen/last-wallpaper"
if [[ -s "$last" ]]; then
    wp="$(head -1 "$last")"
    [[ -e "$wp" ]] && exec setbg "$wp"
fi
exec setbg
EOF
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n /etc/nixos/mandragora/.local/bin/restore-theme.sh && echo "OK"
```

Expected: `OK`

- [ ] **Step 3: Commit**

```bash
cd /etc/nixos/mandragora
git add .local/bin/restore-theme.sh
git commit -m "feat: restore-theme reads from matugen cache"
```

---

### Task 9: Update rofi theme to import from matugen cache

**Files:**
- Modify: `.config/rofi/theme.rasi`

Currently imports `~/.cache/wal/colors-rofi.rasi`. Change to matugen output path.

- [ ] **Step 1: Update the import line**

```bash
sed -i 's|~/.cache/wal/colors-rofi.rasi|~/.cache/matugen/colors-rofi.rasi|' \
    /etc/nixos/mandragora/.config/rofi/theme.rasi
```

- [ ] **Step 2: Verify the change**

```bash
head -1 /etc/nixos/mandragora/.config/rofi/theme.rasi
```

Expected: `@import "~/.cache/matugen/colors-rofi.rasi"`

- [ ] **Step 3: Commit**

```bash
cd /etc/nixos/mandragora
git add .config/rofi/theme.rasi
git commit -m "feat: rofi theme imports matugen colors instead of wal"
```

---

### Task 10: Update home.nix — packages and config declarations

**Files:**
- Modify: `modules/user/home.nix`

Four changes: (a) add packages, (b) remove pywal+wal-to-rgb, (c) update kitty colors include, (d) swap home.file entries.

- [ ] **Step 1: Add quickshell and matugen to packages (after the openrgb line)**

In `modules/user/home.nix` around line 183, replace:
```nix
    openrgb
    pywal
```
with:
```nix
    openrgb
    quickshell
    matugen
```

- [ ] **Step 2: Remove walToRgbEnv let binding (line ~11)**

In `modules/user/home.nix`, remove this line from the `let` block:
```nix
  walToRgbEnv = pkgs.python3.withPackages (ps: with ps; [ openrgb-python ]);
```

- [ ] **Step 3: Remove wal-to-rgb writeShellScriptBin entry (around line 244)**

Remove this entire line:
```nix
    (pkgs.writeShellScriptBin "wal-to-rgb" ''exec ${walToRgbEnv}/bin/python3 ${../../.local/bin/wal-to-rgb.py} "$@"'')
```

- [ ] **Step 4: Update kitty extraConfig (around line 457)**

Replace:
```nix
    extraConfig = "include ~/.cache/wal/colors-kitty.conf";
```
with:
```nix
    extraConfig = "include ~/.cache/matugen/colors-kitty.conf";
```

- [ ] **Step 5: Remove wal home.file entries (around lines 624-625)**

Remove these two lines:
```nix
  home.file.".config/wal/templates/keyledsd.conf".source = ../../.config/wal/templates/keyledsd.conf;
  home.file.".config/wal/templates/colors-rofi.rasi".source = ../../.config/wal/templates/colors-rofi.rasi;
```

- [ ] **Step 6: Add home.file entries for quickshell and matugen configs**

Add after the tridactyl entry (around line 622), before `home.activation.seedKeyledsd`:
```nix
  home.file.".config/quickshell" = {
    source = ../../.config/quickshell;
    recursive = true;
  };

  home.file.".config/matugen" = {
    source = ../../.config/matugen;
    recursive = true;
  };
```

- [ ] **Step 7: Verify home.nix parses (Nix syntax check)**

```bash
nix-instantiate --parse /etc/nixos/mandragora/modules/user/home.nix > /dev/null && echo "OK"
```

Expected: `OK` (no output to stderr, exits 0)

- [ ] **Step 8: Commit**

```bash
cd /etc/nixos/mandragora
git add modules/user/home.nix
git commit -m "feat: add quickshell+matugen, remove pywal, update kitty+rofi config in home.nix"
```

---

### Task 11: Update Hyprland keybind

**Files:**
- Modify: `.config/hypr/hyprland.conf`

- [ ] **Step 1: Change SUPER+G from setbg to quickshell**

```bash
sed -i 's|^bind = \$mainMod, G, exec, setbg$|bind = $mainMod, G, exec, quickshell|' \
    /etc/nixos/mandragora/.config/hypr/hyprland.conf
```

- [ ] **Step 2: Verify the change**

```bash
grep "mainMod, G" /etc/nixos/mandragora/.config/hypr/hyprland.conf | grep -v CTRL | grep -v SHIFT | grep -v ALT
```

Expected:
```
bind = $mainMod, G, exec, quickshell
```

- [ ] **Step 3: Commit**

```bash
cd /etc/nixos/mandragora
git add .config/hypr/hyprland.conf
git commit -m "feat: SUPER+G launches quickshell wallpaper picker"
```

---

### Task 12: NixOS rebuild

- [ ] **Step 1: Run rebuild**

```bash
sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora-desktop 2>&1 | tail -20
```

Expected: build succeeds, no errors about `walToRgbEnv` or missing `pywal`.

- [ ] **Step 2: Verify quickshell and matugen are in PATH**

```bash
which quickshell && quickshell --version
which matugen && matugen --version
```

Expected: both commands found with version strings.

- [ ] **Step 3: Verify config files were linked**

```bash
ls ~/.config/quickshell/
ls ~/.config/matugen/templates/
```

Expected: `quickshell/` contains `Main.qml`, `MatugenColors.qml`, `Scaler.qml`, `WindowRegistry.js`, `wallpaper/`. `matugen/templates/` contains the three template files.

- [ ] **Step 4: Verify matugen can run against a wallpaper**

Pick any jpg from `~/Pictures/wllpps/` and run matugen against it:
```bash
wp=$(find ~/Pictures/wllpps -name "*.jpg" -o -name "*.png" | head -1)
matugen image "$wp" && echo "OK"
```

Expected: `OK`, and `/tmp/qs_colors.json`, `~/.cache/matugen/colors-kitty.conf`, `~/.cache/matugen/colors-rofi.rasi` are created.

```bash
ls -la /tmp/qs_colors.json ~/.cache/matugen/
```

- [ ] **Step 5: Verify matugen kitty output is valid**

```bash
head -5 ~/.cache/matugen/colors-kitty.conf
```

Expected: lines like `foreground #xxxxxx` — actual hex colors, not template placeholders.

---

### Task 13: Smoke test

- [ ] **Step 1: Test SUPER+G opens the picker**

Press `SUPER+G`. The QuickShell picker should appear as a fullscreen overlay with a grid of wallpapers from `~/Pictures/wllpps`.

If nothing appears, check quickshell logs:
```bash
journalctl --user -xe | grep -i "quickshell\|qs-wallpaper" | tail -20
```

- [ ] **Step 2: Pick a wallpaper — verify transition and color reload**

Click a wallpaper thumbnail. Verify:
1. The picker overlay closes immediately
2. The wallpaper transitions with awww animation
3. Kitty terminal colors update (open a new kitty window or `killall -USR1 .kitty-wrapped`)
4. Waybar colors update
5. `~/.cache/matugen/last-wallpaper` contains the path

```bash
cat ~/.cache/matugen/last-wallpaper
```

- [ ] **Step 3: Test ESC dismisses without changing wallpaper**

Press `SUPER+G`, then press ESC. Current wallpaper should be unchanged.

- [ ] **Step 4: Test DDG online search tab**

Open picker with `SUPER+G`. Click the "Search" filter tab. Type a query (e.g. "forest"). Verify thumbnail grid populates with downloaded images.

- [ ] **Step 5: Test restore-theme on login**

Check that `~/.cache/matugen/last-wallpaper` exists from step 2. Then manually test restore:
```bash
restore-theme
```

Expected: wallpaper is reapplied (awww transition) and colors re-generated.

- [ ] **Step 6: Test ALT+SUPER+G rofi picker still works**

Press `ALT+SUPER+G`. Rofi file picker should appear. Selecting a wallpaper should call `setbg` which now uses matugen.

- [ ] **Step 7: Verify zero Hyprland config errors**

```bash
hyprctl configerrors
```

Expected: empty output.
