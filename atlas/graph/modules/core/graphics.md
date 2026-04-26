---
type: module
layer: core
tags: [module, core, nvidia, wayland, hardware]
path: modules/core/graphics.nix
---

# graphics.nix

NVIDIA driver setup + the **`mandragora.hardware.gpu.vramGB`** declaration that the rest of the system gates on.

## Role
- `nvidia` + `amdgpu` video drivers; open-source kernel module + beta package.
- Modesetting + power management on; 32-bit graphics enabled (Steam, Wine).
- Loads `nvidia`, `nvidia_modeset`, `nvidia_drm`, `nvidia_uvm` kernel modules.
- Sets `mandragora.hardware.gpu.vramGB = 16` — read by other modules to gate VRAM-hungry features.

## Connections
- Up: [[../_index|Modules]]
- Consumed by: [[ai-local]] (asserts `vramGB >= 16` for agentic stack), [[../desktop/hyprland]] (Wayland NVIDIA env vars)
- Pairs with: [[boot]] (kernel modules), [[monitoring]] (NVIDIA GPU metrics)
- Touches: [[../../concepts/nvidia]], [[../../concepts/wayland]]
