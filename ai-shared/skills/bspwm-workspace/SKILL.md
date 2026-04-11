---
name: bspwm-workspace
description: Add a new workspace for an application, wiring up bspwm workspaces, polybar icons, and external rules in one atomic operation.
---

# Add Workspace to bspwm + polybar

## Goal
Add a new workspace for an application, wiring up bspwm workspaces, polybar icons, and external rules in one atomic operation.

## Prerequisites

- bspwm window manager at `~/.config/bspwm/bspwmrc`
- polybar config at `~/.config/polybar/config.ini`
- external rules script at `~/.config/bspwm/external_rules`
- Workspace icons defined in `[module/bspwm]` section of polybar config
- polybar has multiple fonts loaded (typically `Font Awesome 7 Free Solid` as font-9, `Font Awesome 7 Brands` as font-10, `forkawesome` as font-11)

## Steps

### 1. Gather information
- Ask user for: **app name** (e.g. "obsidian"), **icon** (unicode glyph or icon name)
- If app is currently open, determine its WM_CLASS:
  ```bash
  xdotool search --name "" | while read wid; do xprop -id "$wid" WM_CLASS 2>/dev/null | grep -i <app-name> && echo "WIN_ID=$wid"; done | head -5
  ```
- Determine the **next available workspace number** (count existing `ws-icon-N` entries in polybar config, and count workspaces in the `bspc monitor -d` line in bspwmrc)
- Convert to Roman numeral for the workspace name (I, II, III, ... XL, XLI, XLII, etc.)

### 2. Determine which font the icon belongs to

Check which Font Awesome variant contains the icon:
- **Solid** icons: use `font-9` (index 9 in polybar, referenced as `%{T9}`)
- **Brands** icons: use `font-10` (index 10, referenced as `%{T10}`)
- **Regular** icons: use the Regular variant if loaded
- If unsure, check with `fc-list | grep -i "font awesome"`

If the icon is a **Brands** icon (like Obsidian), it needs explicit font tag because the bspwm module uses `label-*-font = 9` (Solid) by default.

### 3. Update polybar config (`~/.config/polybar/config.ini`)

In the `[module/bspwm]` section, add a new `ws-icon-N` entry:

**Solid icon** (most common):
```
ws-icon-40 = XLI;
```

**Brands icon** (needs font switch):
```
ws-icon-40 = XLI;%{T11}%{T-}
```
`%{T11}` references the 1-based font index (font-10 = T11 due to font-0 being T1). `%{T-}` resets back to default.

### 4. Update bspwmrc (`~/.config/bspwm/bspwmrc`)

Add the new Roman numeral workspace to the `bspc monitor -d` line:
```
bspc monitor -d I II III ... XL XLI
```
Just append the new Roman numeral after existing ones, space-separated.

### 5. Update external rules (`~/.config/bspwm/external_rules`)

Add a rule at the end of the file (before the last entry, keeping it at the end):
```bash
if [ "$class" = "<app-wm-class>" ]; then
	echo "desktop=^<workspace-index> follow=true"
fi
```

Where:
- `<app-wm-class>` is the WM_CLASS from step 1 (e.g. `"obsidian"`)
- `<workspace-index>` is the **1-based index** matching the position in the `bspc monitor -d` line (^41 for the 41st workspace)

**Common variations:**
- If the app should NOT steal focus, omit `follow=true`
- If the app should always follow focus, add `follow=on`
- Some apps need both class variants checked (e.g. `"obsidian"` and `"Obsidian"`)

### 6. Verification

Confirm all three files are consistent:
1. polybar has `ws-icon-N` for the new workspace
2. bspwmrc has the workspace in `bspc monitor -d`
3. external_rules has the class → desktop mapping

### 7. Apply changes

Tell user to restart bspwm and polybar:
```bash
bspc wm -r
pkill polybar; polybar mybar &
```

## Roman Numeral Reference
```
1=I     11=XI     21=XXI    31=XXXI   41=XLI
2=II    12=XII    22=XXII   32=XXXII  42=XLII
3=III   13=XIII   23=XXIII  33=XXXIII 43=XLIII
4=IV    14=XIV    24=XXIV   34=XXXIV  44=XLIV
5=V     15=XV     25=XXV    35=XXXV   45=XLV
6=VI    16=XVI    26=XXVI   36=XXXVI  46=XLVI
7=VII   17=XVII   27=XXVII  37=XXXVII 47=XLVII
8=VIII  18=XVIII  28=XXVIII 38=XXXVIII 48=XLVIII
9=IX    19=XIX    29=XXIX   39=XXXIX  49=XLIX
10=X    20=XX     30=XXX    40=XL     50=L
```

## Quick Example

**User:** "Add Obsidian to a new workspace with icon "

1. WM_CLASS: `obsidian`
2. Icon  is Brands → needs font tag
3. Next workspace: 41 → Roman: XLI, index: ^41
4. polybar: `ws-icon-40 = XLI;%{T11}%{T-}`
5. bspwmrc: append `XLI` to `bspc monitor -d` line
6. external_rules: add rule for `obsidian` → `desktop=^41 follow=true`
