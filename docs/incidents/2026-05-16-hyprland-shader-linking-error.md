# Incident Report: Hyprland Shader Linking Error (C3001)

**Date:** 2026-05-16  
**Status:** Resolved  
**Severity:** High (UI disruption, blocking banner)

## Symptom
A persistent red banner at the top of the Hyprland session displaying:
> "Screen shader parser: Error linking program:Fragment info"
> "error C3001: no program defined"
> "Hyprland may not work correctly"

The banner was non-selectable and obstructed the view, significantly impacting usability.

## Root Cause
The incident had two primary drivers:

1.  **Non-Atomic File I/O:** The Waybar brightness script (`brightness.sh`) was updating the fragment shader file (`~/.cache/hypr/brightness.frag`) using standard redirection (`cat > file`). This created a window where the file was empty or partially written while Hyprland was attempting to reload it.
2.  **GLSL Versioning:** The NVIDIA driver/Hyprland environment required an explicit `#version` tag and specific precision qualifiers that were absent in the generated shader, causing linking failures on the compiled program.

## Mitigation & Resolution
The following steps were taken to resolve the error and prevent recurrence:

### 1. Script Hardening
Updated `nix/snippets/waybar-brightness.sh` to use an atomic "write-then-move" pattern:
```bash
local tmp_file="$SHADER_FILE.tmp"
cat >"$tmp_file" <<EOF
#version 120
precision mediump float;
// ... shader code
EOF
mv "$tmp_file" "$SHADER_FILE"
```
This ensures Hyprland never reads an incomplete file.

### 2. Shader Compatibility
Added `#version 120` and simplified the fragment shader syntax to ensure broad compatibility with the NVIDIA GLSL parser.

### 3. Build-Time Validation (CI/CD)
The Nix build check `hyprlandConfigGuard` in `nix/modules/shared/build-checks.nix` was found to be ineffective as it pointed to a non-existent path (`/etc/hyprland.conf`) and used an obsolete flag.

It has been updated to verify the **actual** repository-source Hyprland configuration using the modern flag:
```nix
${pkgs.hyprland}/bin/Hyprland --verify-config -c "$conf"
```
Any future syntax or static parser errors will now cause `mandragora-switch` to fail, preventing broken configurations from being deployed to the live session.

## Lessons Learned
- **UI Error Visibility:** System-level UI error banners (CHyprError) are not always captured in standard journal logs and require direct inspection of the Hyprland log file and `hyprctl configerrors`.
- **Atomic Operations:** Any file watched by a compositor for runtime reloads MUST be updated atomically.
- **Validation Drift:** Build-time checks must be periodically audited to ensure they are pointing to active configuration paths and using correct binary flags.
