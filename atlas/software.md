# Mandragora Software: The Linux Sovereignty Stack

This document defines the software stack for the Mandragora NixOS environment, focusing on hardware-specific drivers, peripheral control, and optimization.

## 1. Graphics Stack (NVIDIA + Wayland)

### **Drivers**
- **Kernel Module**: `nvidia` (Proprietary)
- **Wayland Integration**: GBM (Generic Buffer Management) enabled.
- **Known Bugs & Risks**:
  - Explicit sync issues causing flickering in XWayland applications.
  - Suspend/resume state corruption for video memory.
- **Optimizations & Mitigations**: 
  - `nvidia_drm.modeset=1` kernel parameter.
  - `nvidia.NVreg_PreserveVideoMemoryAllocations=1` to mitigate suspend/resume corruption.
  - `__GLX_VENDOR_LIBRARY_NAME=nvidia` for hardware acceleration.
  - `WLR_NO_HARDWARE_CURSORS=1` (if cursor flicker occurs).

## 2. Peripheral & Aesthetic Control

### **RGB Management (OpenRGB)**
- **Target**: Kingston Fury Beast RAM, MSI MAG AIO (if addressable via ARGB header).
- **Automation**: Managed via Nix-defined OpenRGB profiles, synchronized with the "Dynamic Skin" (Pywal).
- **Kingston Specifics**: OpenRGB supports many Kingston models; however, EXPO v1.1 modules (CL30) may require **manual mapping** if not immediately detected.
- **Fallback**: Configure once in Windows/BIOS if the hardware supports internal RGB state persistence (documented in legacy `RGB_LINUX.md`).

### **Fan & Pump Control**
- **Method**: UEFI BIOS curves (preferred for stability).
- **Software (Alternative)**: `liquidctl` or `coolercontrol` for monitoring pump speed and liquid temperature if supported by the MSI MAG AIO.

### **Monitoring Displays**
- **Option A (8.8" Bar LCD)**: High-resolution dashboard via specialized Python monitoring scripts.
- **Option B (4" Square RGB)**: Requires porting the **Serial Sender** Python logic from `~/util/pc-novo/st7701s_qualia`. This formats real-time metrics into a serial stream.
- **Snippet Requirement**: Move all legacy Python display logic to `snippets/python/` for Nix integration.

## 3. Performance & Stability

### **Ryzen 9 7900X Tuning**
- **PBO (Precision Boost Overdrive)**: Eco Mode (65W/105W) or negative Curve Optimizer offsets to manage thermals in the Lian Li A3.
- **NixOS CPU Scheduler**: `power-profiles-daemon` or `auto-cpufreq` to balance performance and power.

### **Kernel Tweaks**
- **Zen Kernel (Optional)**: If lower latency is needed for creative work.
- **IOMMU**: Enabled for potential VM passthrough experiments (arch-slave offloading).

## 4. Hardware Auditing Modules
The `audits/` modules in Mandragora will specifically track:
- **NVMe SMART Status**: Health of the 2TB Kingston NV3.
- **Thermal Anomalies**: Continuous monitoring of CPU/GPU temps via `lm-sensors`.
- **GPU Driver Mismatch**: Ensuring the active `nvidia` driver version matches the kernel.
