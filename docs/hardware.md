# Hardware

The Mandragora workstation. Single SFF build; one entry per piece.

| Component | Choice |
|-----------|--------|
| **CPU** | AMD Ryzen 9 7900X (12C/24T, boost up to 5.6 GHz, 170 W TDP / 230 W PPT) |
| **GPU** | RTX 5070 Ti — Gigabyte Windforce SFF 16 GB (GDDR7, 304 mm length) |
| **RAM** | 32 GB (2×16 GB) DDR5 6000 MT/s CL30 — Kingston Fury Beast (AMD EXPO v1.1) |
| **Motherboard** | Gigabyte B650M AORUS ELITE AX WIFI (mATX; 1× PCIe 5.0 x4 M.2, 1× PCIe 4.0 x4 M.2; 4 DDR5 slots) |
| **Case** | Lian Li A3-mATX (26.3 L, modular PSU mounting) |
| **Cooler** | MSI MAG Coreliquid A13 (360 mm AIO, ARGB; top-mounted exhaust) |
| **PSU** | Thermaltake Toughpower GF A3 850 W (ATX 3.0, native 12VHPWR/12V-2x6, fully modular) |
| **Storage** | 2 TB Kingston NV3 PCIe 4.0 |

## Initial-boot ritual

1. Assemble and boot with the Ryzen 7900X iGPU (no discrete card yet).
2. Verify BIOS stability, RAM EXPO profile, basic thermals.
3. Install the RTX 5070 Ti only after the base system is confirmed stable.

## Peripheral control on Linux

| Subsystem | Tool / mechanism |
|-----------|------------------|
| GPU monitoring | `nvidia-smi`, `gwe` (GreenWithEnvy) |
| AIO / fans | UEFI BIOS curves preferred for stability; `liquidctl` or `coolercontrol` for monitoring (MSI MAG support varies) |
| RAM RGB | `OpenRGB` (Kingston Fury Beast — EXPO v1.1 CL30 may need manual mapping) |

## NVIDIA + Wayland tuning

Declarative config in `modules/core/graphics.nix`:

- `hardware.nvidia.open = true` — open-source kernel modules (matches the
  RTX 5070 Ti's Blackwell architecture, which the open driver supports).
- `hardware.nvidia.modesetting.enable = true` — sets `nvidia_drm.modeset=1`
  internally; required for Wayland.
- `hardware.nvidia.powerManagement.enable = true`.
- `hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.beta`
  — 570.x beta from `nixos-unstable`.
- `boot.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_drm" "nvidia_uvm" ]`.
- `services.xserver.videoDrivers = [ "nvidia" "amdgpu" ]` — `amdgpu` is
  for the Ryzen 7900X iGPU (used during the initial-boot ritual above).

Per-session env in `modules/desktop/hyprland.nix`:

- `__GLX_VENDOR_LIBRARY_NAME=nvidia` — hardware acceleration for GLX clients.

`WLR_NO_HARDWARE_CURSORS=1` and `NVreg_PreserveVideoMemoryAllocations` are
**not currently set**. Add them only if cursor flicker or suspend/resume
video-memory corruption shows up; the open kernel module has historically
not needed them.
