# Mandragora Structure: The AI-Optimized Map

## 1. Top-Level Organization

```text
.
├── flake.nix
├── hosts/
│   └── mandragora-desktop/    # Primary workstation
│       ├── hardware-configuration.nix
│       └── default.nix
├── modules/
│   ├── core/                  # System-level: globals, persistence, kernel
│   ├── desktop/               # Hyprland, SDDM, PipeWire, gaming, RGB
│   └── user/                  # Home Manager: Kitty, Firefox, theming
├── snippets/                  # Non-Nix logic (shell, Python, CSS)
├── secrets/                   # sops-nix encrypted vaults
├── atlas/                     # Hardware specs, constraints, partition plan
└── appendix/                  # Self-contained subprojects (Ventoy USB)
```

## 2. Documentation

```text
.
├── README.md                  ← Front door: Mermaid diagrams, quick reference
├── DECISIONS.md               ← ALL resolved technical choices
├── AGENTS.md                  ← Routing table for AI sessions
├── EXECUTION_PLAN.md          ← Build checklist with checkboxes
├── SITUATIONS.md              ← Day-to-day tactical decisions
├── DATA_HIERARCHY.md          ← 5-tier persistence/backup matrix
├── WORKFLOW.md                ← Sync ritual: Flake=Git, Seafile=user data
├── SECRETS.md                 ← sops-nix vault strategy
├── SHADOW.md                  ← Shadow profile architecture
├── STRUCTURE.md               ← This file
└── atlas/
    ├── PARTITION_PLAN.md      ← Disk layout, Btrfs subvolumes
    ├── hardware.md            ← Physical specs and assembly
    ├── software.md            ← Drivers, RGB, monitoring
    ├── non-negotiables.md     ← Hard constraints
    ├── ideation.md            ← Evolving wishlist
    ├── TODO.md                ← Execution roadmap checkboxes
    ├── inspiration.md         ← External references
    └── PRD.md                 ← Vision and profiles (reference)
```

## 3. The "Dynamic Skin" (Planned)

- **`theming.nix`:** Will consume `colors.json` from Pywal-style hook.
- **Workflow:** Wallpaper -> Color extraction -> Nix palette -> Home-manager reload.
- **Status:** Not yet implemented. Files do not exist yet.

## 4. Sync & Compute Orchestration

- **Seafile:** User data synchronization, self-hosted on `arch-slave`.
- **GitHub:** System logic (Nix Flake) version control.
- **arch-slave:** External Arch Linux machine — Seafile server, bulk storage, and reference. Not managed by this flake.
