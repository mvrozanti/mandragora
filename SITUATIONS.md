# Mandragora Situations: The Real-World Decisions

This document identifies the tactical, day-to-day "forks in the road" you will encounter once Mandragora is alive.

## 1. The "Hyprland Broke My Config" Situation
- **The Problem:** You're on `nixpkgs-unstable`. A new Hyprland commit changes the syntax of a "blur" setting. Your UI crashes on rebuild.
- **The Decision:**
    - **A)** **Flake Locking:** Pin the Hyprland flake input to a specific "known good" commit.
    - **B)** **The Rolling Risk:** Stay on the bleeding edge and accept that "Ricing Sessions" might occasionally turn into "Fixing My UI" sessions.

## 2. The "Development Environment" Situation
- **The Problem:** You're working on a Python project that needs `libxml2` and a specific version of `gcc`.
- **The Friction:** Installing these globally in NixOS is an anti-pattern and leads to "Dependency Hell."
- **The Decision:**
    - **The `direnv` + `nix-shell` Ritual:** Every project directory gets a `shell.nix` or `flake.nix`. When you `cd` into it, the environment (compilers, libs) is instantly and temporarily added to your shell. This is a massive workflow shift from Arch.

## 3. The "Nix Store Bloat" Situation
- **The Problem:** You've done 50 rebuilds while ricing. Your `/nix/store` is now 150GB.
- **The Decision:**
    - **The "Gold" Generation:** Every push to the main configuration repository triggers a documentation update in the README. We will link the specific Nix generation to its corresponding Git commit, recording its unique ID and total on-disk footprint. These "Gold" generations are explicitly pinned to prevent deletion during automated garbage collection cycles.

## 4. The "Fonts & Icons" Situation
- **The Problem:** You have a collection of 100+ "impure" fonts from your Arch days.
- **The Decision:**
    - **A)** **The Nix-native Way:** Package each font as a derivation (proper, but slow).
    - **B)** **The "Legacy Font" Folder:** Use `fonts.fontDir.enable = true;` and symlink your old fonts folder. It's "dirty," but it works.
