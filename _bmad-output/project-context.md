# Project Context: Mandragora NixOS

## 1. Project Overview
- **Name**: Mandragora NixOS
- **Type**: System Configuration (Nix Flake)
- **Vision**: Create a high-performance, purely declarative "second skin" Linux workstation. It serves as the final destination for system design, combining raw hardware power with a deeply integrated, dynamic aesthetic.
- **Key Characteristics**: Nix-managed, Wayland/Hyprland-centric, NVIDIA-optimized, visually integrated ("Dynamic Rice"), and enforcing strict profile isolation (Mandragora vs. Shadow).

## 2. Core Architecture & Non-Negotiables
- **Declarative Sovereignty**: Every system configuration, app setting, and driver MUST be defined in the Nix Flake. No imperative changes (`chmod`, `systemctl` manually). If it's worth changing, it's worth Nixifying.
- **NVIDIA + Wayland Only**: Strict adherence to Wayland utilizing proprietary NVIDIA drivers (GBM enabled). No X11 fallback.
- **Data & Secret Management**: Zero plain-text secrets in git (`sops-nix` required). Strict adherence to a persistence hierarchy ensuring survival from hardware failure.
- **External Logic Separation**: All non-Nix logic (Python, Shell, CSS) MUST be stored in `snippets/` and imported into `.nix` files to maintain language purity.
- **Physical Isolation**: Development of this new system must not taint the existing reference machine.

## 3. Hardware Foundation (Lian Li A3-mATX SFF Build)
- **CPU**: AMD Ryzen 9 7900X (12C/24T) - Setup with PBO/Eco-mode for SFF thermals.
- **GPU**: NVIDIA RTX 5070 Ti 16GB GDDR7 (Gigabyte Windforce SFF).
- **RAM**: 32GB DDR5 6000MHz CL30 (Kingston Fury Beast).
- **Storage**: 2TB Kingston NV3 PCIe 4.0.
- **Motherboard**: Gigabyte B650M AORUS ELITE AX WIFI.
- **Cooling/PSU**: MSI MAG Coreliquid A13 (360mm ARGB) and Thermaltake Toughpower GF A3 850W (ATX 3.0).

## 4. Software Stack & Integration
- **Compositor**: Hyprland (performance & high-aesthetic tiling/animations).
- **Visuals/Theming**: "Dynamic Skin" pipeline (Wallpaper -> Color Extraction -> Dynamic CSS/JSON injection via Pywal/Stylix) driving Kitty, Neovim, Waybar, and GTK.
- **Hardware Control**: OpenRGB for lighting. Custom Python scripts (to be placed in `snippets/`) for driving external monitoring displays (8.8" Bar LCD or 4" ST7701S).
- **Auditing**: AI-driven system audits (e.g., `modules/audits/strays.sh`, SMART status, thermal monitoring).

## 5. Key Directories & AI Routing
- **`atlas/hardware.md`**: Physical build details, clearance, and rituals. *(Read before hardware suggestions)*.
- **`atlas/software.md`**: Drivers, peripheral control, performance optimizations. *(Read before software suggestions)*.
- **`atlas/non-negotiables.md`**: Core constraints and architectural rules. *(Cross-reference before any system modification)*.
- **`atlas/PRD.md`**: Core product requirements and profiles.
- **`modules/`**: NixOS module definitions (e.g., `core/globals.nix`).
- **`snippets/`**: External scripts/assets to be imported into Nix.
