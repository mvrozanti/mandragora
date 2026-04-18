# Mandragora Non-Negotiables: The Soul of the System

This document defines the core constraints, architectural "must-haves," and the values that define the Mandragora workstation.

## 1. Declarative Sovereignty

### **Nix Supremacy**
- **Constraint**: Every system configuration, application setting, and hardware driver MUST be defined in the Nix Flake.
- **Goal**: Reproducibility. The ability to reconstruct the entire machine from scratch in < 30 minutes.

### **No Imperative Tweaks**
- **Constraint**: Any change made via `chmod`, `systemctl`, or manual file editing (outside of designated stateful areas) is considered technical debt.
- **Rule**: If it's worth changing, it's worth Nixifying.

## 2. Hardware DNA

### **NVIDIA + Wayland Only**
- **Decision**: No fallback to X11. The system is built for the high-performance, high-aesthetic future of Hyprland/Wayland.
- **Reason**: To push the boundaries of modern Linux desktop performance and visuals.

### **Pure Linux Environment**
- **Constraint**: Zero Windows on primary SSD. The machine is a dedicated NixOS workstation.
- **Isolation**: Any gaming or external drive needs (Windows compatibility) MUST be physically isolated (external drives).
- **Exception (Corporate/Laptop)**: If forced to use Windows on another machine (e.g., a work laptop), a WSL profile can be used to adapt the environment. See [WSL Appendix](../appendix/wsl/README.md).

## 3. Data Integrity & Persistence

### **The Persistence Matrix**
- **Constraint**: Adherence to `DATA_HIERARCHY.md` (Rank 1 to 5).
- **Rule**: Critical data MUST survive a catastrophic hardware failure of the primary drive.

### **Zero-Secret Commits**
- **Constraint**: Use `sops-nix` or equivalent for all secrets. Never commit a plain-text API key, password, or SSH key.

## 4. The Profile Paradox (Mandragora vs. Shadow)

### **Mandragora (The Creator)**
- **Value**: High-performance, creative, audited, AI-integrated.
- **Role**: The "Serious" workstation.

### **Shadow (The Consumer)**
- **Value**: Casual, isolated, aesthetic, private.
- **Role**: The "Shadow" environment.
- **Constraint**: Zero visibility or crossover between Shadow and Mandragora (boot-level isolation).

## 5. Physical Isolation & Sovereignty

### **The Isolation Protocol**
- **Constraint**: During the configuration and bootstrap of the new Mandragora system, **NOTHING** shall be written to or deleted from the current reference machine (Arch).
- **Goal**: Maintain the Arch machine as a pure, static reference and prevent "split-brain" configuration errors.
- **Rule**: All new logic, Nix expressions, and system state must be committed to the new hardware or the Oracle VPS repository only.

## 6. Architectural Cleanliness

### **External Snippets**
- **Rule**: All non-Nix logic (Python scripts, CSS themes, Shell scripts) MUST be stored in `snippets/` and imported into the Nix config.
- **Reason**: To avoid string-embedding and maintain language purity in `.nix` files.
