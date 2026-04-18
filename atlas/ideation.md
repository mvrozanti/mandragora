# Mandragora Ideation: The Evolving Horizon

This document captures the future possibilities, experimental features, and "blue-sky" ideas for the Mandragora ecosystem.

## 1. High-Priority Experiments

### **Internal System Monitoring (The "Dashboard")**
We are evaluating two primary hardware paths for the internal system dashboard:

- **Option A: The Bar (8.8" LCD)**
    - **Hardware**: 8.8" Universal LCD Screen (1920x480p, USB/ARGB) - [SM088X](https://www.pcgamerbrasilia.com.br/tela-lcd-88-universal-para-gabinetes-lian-li-preto-argb-1920x480p-usb-sm088x).
    - **Vibe**: High-resolution, wide-aspect "command strip" integrated into the Lian Li A3 mesh.
- **Option B: The Square (4" RGB)**
    - **Hardware**: 4-inch ST7701S / Qualia RGB Display.
    - **Vibe**: Compact, square aesthetic for focused metrics, potentially mounted internally.
    - **Note**: Requires the serial sender/microcontroller logic documented in `~/util/pc-novo/st7701s_qualia`.

### **The "Trap" (Shadow Profile Security)**
- **Concept**: A `udev` trigger that locks the system into the Shadow profile unless a specific encrypted USB key is inserted.
- **Possibility**: Physical haptics or specialized audio-cues when switching between Mandragora (Serious) and Shadow (Casual) modes.

## 2. Long-Term Possibilities

### **Impermanence (Erase Your Darlings)**
- **Status**: **PROMOTED TO DAY 1 REQUIREMENT** (See `TODO.md`).
- **Goal**: Root-on-tmpfs implementation to ensure a perfectly clean, reproducible system at all times.

### **Declarative Soundscapes**
- **Concept**: Using Nix to define not just the UI (Rice) but also the auditory environment.
- **Feature**: Specialized system sounds that change based on the current active color palette (Stylix/Pywal integration).

### **Nyxt Browser Mastery**
- **Goal**: Transition from standard browsers (Firefox/Brave) to Nyxt (Lisp-powered, hackable).
- **Reason**: Fits the "Second Skin" ethos where every tool is an extension of the user's workflow.

## 3. "The Final PC" Vision
- **Goal**: A zero-maintenance (software-wise), high-performance workstation that can be rebuilt from a single GitHub push to any hardware.
- **Aesthetic**: A perfectly unified look across all screens, peripherals, and physical lighting.
