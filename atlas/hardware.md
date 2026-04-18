# Mandragora Hardware: The Physical DNA

This document details the hardware components of the Mandragora workstation, their technical specifications, and compatibility considerations.

## 1. Primary Components (The Build)

### **CPU: AMD Ryzen 9 7900X**
- **Cores/Threads**: 12C/24T
- **Boost Clock**: Up to 5.6GHz
- **TDP**: 170W (PPT up to 230W)
- **Status**: ✅ **COMPRADO**

### **GPU: RTX 5070 Ti (Gigabyte Windforce SFF 16G)**
- **Memory**: 16GB GDDR7
- **Length**: 304mm
- **Status**: ✅ **COMPRADO**
- **Note**: Wayland compatibility via NVIDIA proprietary drivers (GBM).

### **RAM: 32GB (2x16GB) DDR5 6000MHz CL30 (Kingston Fury Beast)**
- **Profile**: AMD EXPO v1.1
- **Status**: ✅ **COMPRADO**
- **RGB**: Controlled via OpenRGB.

### **Motherboard: Gigabyte B650M AORUS ELITE AX WIFI**
- **Format**: mATX
- **M.2 Slots**: 1x PCIe 5.0 x4, 1x PCIe 4.0 x4
- **DDR5 Slots**: 4
- **Status**: 📦 **FIXADO (Falta Comprar)**

### **Case: Lian Li A3-mATX**
- **Volume**: 26.3L
- **Format**: Micro-ATX (modular PSU mounting)
- **Status**: ✅ **COMPRADO**

### **Cooler: MSI MAG Coreliquid A13 (360mm ARGB)**
- **Radiator**: 360mm
- **Status**: ✅ **COMPRADO**
- **Configuration**: Top-mounted exhaust.

### **PSU: Thermaltake Toughpower GF A3 850W**
- **Standard**: ATX 3.0 (Native 12VHPWR/12V-2x6)
- **Modular**: Fully Modular
- **Status**: ✅ **COMPRADO**

### **Storage: 2TB Kingston NV3 PCIe 4.0**
- **Status**: ✅ **COMPRADO**

## 2. Compatibility & Clearance Notes (Lian Li A3)

... [Clearance notes] ...

## 3. Hardware Assembly Rituals (Infused from Legacy)

### **The Initial Boot Ritual**
- **Step 1**: Assemble and boot using the **Ryzen 9 7900X Integrated Graphics** (iGPU).
- **Step 2**: Verify BIOS stability, RAM EXPO profiles, and basic thermals.
- **Step 3**: Install the RTX 5070 Ti only after the base system is confirmed stable.

## 4. Peripheral Control on Linux
- **GPU**: `nvidia-smi`, `gwe` (GreenWithEnvy).
- **AIO/Fans**: `liquidctl` (MSI MAG support varies) or BIOS curves.
- **RAM**: `OpenRGB`.
- **Display Monitoring**: 
    - **Option A (The Bar)**: 8.8" 1920x480p LCD (SM088X) via USB/HDMI.
    - **Option B (The Square)**: 4" ST7701S / Qualia RGB via serial/microcontroller.
