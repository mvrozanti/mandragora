# Mandragora NixOS

A "second skin" Linux workstation — NVIDIA RTX 5070 Ti, Hyprland, impermanent root, and a 2TB NVMe carved into ranked persistence tiers.

---

## Boot Chain

```mermaid
flowchart TD
    A[UEFI Firmware] --> B[systemd-boot]
    B -->|timeout 0, Space=menu| C[Linux Zen Kernel]
    C -->|systemd initrd| D[SDDM login]
    D -->|Hyprland session| E[PipeWire + OpenRGB + Firefox]
```

## Impermanence Lifecycle

Every boot rotates the root subvolume and rebuilds from the last successful NixOS generation.

```mermaid
flowchart TD
    A[Boot begins] --> B["systemd initrd service: rollback"]
    B --> C["Delete root-active"]
    C --> D["Snapshot root-blank → root-active"]
    D --> E["Mount root-active as /"]
    E --> F["Mount /nix (subvolume)"]
    F --> G["Mount /persistent (subvolume)"]
    G --> H["System starts"]
```

## Disk Layout — Btrfs Subvolume Tree

```mermaid
flowchart TD
    NVMe["2TB Kingston NVMe PCIe 4.0"]
    NVMe --> ESP["ESP (4GB, FAT32)"]
    NVMe --> BTRFS["NIXOS (~1.9TB, Btrfs zstd:1)"]
    NVMe --> SWAP["swap (32GB)"]

    BTRFS --> root_blank["root-blank (clean seed, never mounted)"]
    BTRFS --> root_active["root-active → / (ephemeral, wiped each boot)"]
    BTRFS --> nix["nix → /nix (store, packages, generations)"]
    BTRFS --> persistent["persistent → /persistent (home, secrets, state)"]

    persistent --> home["home/m (~500GB, all user data)"]
    persistent --> shadow_img["shadow.img (50GB, LUKS2 loop → /home/shadow)"]
    persistent --> secrets["secrets/ (age key)"]

    classDef ephemeral fill:#f99,stroke:#333,stroke-width:1px
    classDef persistent fill:#9f9,stroke:#333,stroke-width:1px
    classDef isolated fill:#99f,stroke:#333,stroke-width:1px

    class root_blank,root_active ephemeral
    class home,nix,secrets persistent
    class shadow_img isolated
```

## Data Persistence Flow

```mermaid
flowchart LR
    subgraph "Ephemeral — dies on reboot"
    A["/ (root)"]
    B["/tmp (tmpfs)"]
    C["/run (tmpfs)"]
    end

    subgraph "Persistent — survives"
    D["/persistent/home (all user data)"]
    E["/persistent/log (system logs)"]
    F["/persistent/etc (NetworkManager, SSH keys)"]
    G["/persistent/var/lib (Bluetooth, NixOS state)"]
    H["/nix/store (packages, 7-day GC)"]
    end

    subgraph "Remote — synced"
    I["arch-slave (Seafile, Documents)"]
    J["arch-slave (rsync, Rank 1 photos)"]
    end

    D -. "deferred" .-> J
    D -. "Seafile" .-> I

    style A fill:#f99,stroke:#333
    style B fill:#f99,stroke:#333
    style C fill:#f99,stroke:#333
    style D fill:#9f9,stroke:#333
    style E fill:#9f9,stroke:#333
    style F fill:#9f9,stroke:#333
    style G fill:#9f9,stroke:#333
    style H fill:#9f9,stroke:#333
    style I fill:#99f,stroke:#333
    style J fill:#99f,stroke:#333
```

## Quick Reference

| Topic | File |
|-------|------|
| All resolved decisions | [`DECISIONS.md`](DECISIONS.md) |
| Disk partition plan | [`atlas/PARTITION_PLAN.md`](atlas/PARTITION_PLAN.md) |
| Day-to-day situations | [`SITUATIONS.md`](SITUATIONS.md) |
| Build checklist | [`EXECUTION_PLAN.md`](EXECUTION_PLAN.md) |
| Hardware specs | [`atlas/hardware.md`](atlas/hardware.md) |
| Hard constraints | [`atlas/non-negotiables.md`](atlas/non-negotiables.md) |
| Routing for AI sessions | [`AGENTS.md`](AGENTS.md) |
| Secrets strategy | [`SECRETS.md`](SECRETS.md) |
| Hardware assembly status | [`atlas/README.md`](atlas/README.md) |
| Windows/WSL adaptation | [`appendix/wsl/README.md`](appendix/wsl/README.md) |

## Hardware

| Component | Choice |
|-----------|--------|
| CPU | AMD Ryzen 9 7900X (12C/24T) |
| GPU | RTX 5070 Ti (16GB GDDR7) |
| RAM | 32GB DDR5 6000MHz CL30 |
| Motherboard | Gigabyte B650M AORUS ELITE AX WIFI |
| Case | Lian Li A3-mATX |
| Cooler | MSI MAG Coreliquid A13 (360mm ARGB) |
| PSU | Thermaltake Toughpower GF A3 850W (ATX 3.0) |
| Storage | 2TB Kingston NV3 PCIe 4.0 |
