# Mandragora Data Hierarchy: Ranked Value

This document defines the persistence and protection strategy for all data within the Mandragora ecosystem, from "Invulnerable" to "Ephemeral."

## 1. The Persistence Matrix

| Rank | Data Category       | Priority      | Strategy                           | Location / Mirroring             |
|------|---------------------|---------------|------------------------------------|----------------------------------|
| **1**| **Childhood Photos**| **Invulnerable**| Triple-redundancy + Mirroring      | Local Btrfs RAID1 + Seafile + Slave |
| **2**| **Shadow Drive**    | **Isolated**  | Physical Isolation + LUKS          | Dedicated encrypted partition     |
| **3**| **Movies/Media**    | **Bulk**      | Remote Mount / On-demand           | Hosted on `arch-slave` (SSHFS/NFS)|
| **4**| **Documents**       | **Resilient** | Real-time Sync + History           | Seafile (arch-slave)             |
| **5**| **Public Git**      | **Ephemeral** | Version Control Only               | Local / Re-clonable              |

## 2. Technical Implementation

### Rank 1: The "Invulnerable" Layer
- **Local:** Btrfs RAID1 (if dual-drive) or redundant subvolume snapshots.
- **Remote:** Automated `rsync` or `rclone` to the `arch-slave` node and the Oracle VPS.
- **Constraint:** This data must survive even a catastrophic failure of the primary SSD.

### Rank 2: The "Shadow" Layer
- **Access:** Strictly Shadow-profile only.
- **Mounting:** LUKS-encrypted, UUID-mapped, only present in the Shadow boot entry.

### Rank 3: The "Bulk" Layer
- **Logic:** Does not live on the 2TB primary SSD.
- **Mounting:** Dynamically mounted from the `arch-slave` node via SSHFS or NFS when needed.

### Rank 4: The "Sync" Layer (Seafile)
- **Tool:** `seafile-client` managed via Home Manager.
- **Server:** Self-hosted on the `arch-slave` machine — plenty of storage, local network.
- **Behavior:** Documents are locally cached for speed but are perpetually versioned on `arch-slave`.

## 3. Home Manager Integration
Home Manager will be responsible for ensuring these paths are consistent across both the Desktop and Notebook:
- `~/` — Lives entirely on `/persistent/home` (survives reboots)
- `~/Documents` -> Linked to Seafile sync subvolume.
- `~/Projects` -> Linked to Rank 5 subvolume (clean, no-sync).
- `~/Photos` -> Linked to Rank 1 subvolume (triple redundancy).
- `~/Media` -> Linked to Rank 3 remote mount.
