---
type: module
layer: core
tags: [module, core, storage, btrfs]
path: modules/core/storage.nix
---

# storage.nix

Btrfs subvolumes, zstd compression, mount points.

## Role
- Single `NIXOS` label split across subvols: `root-active`, `nix`, `persistent`, plus a `home/m/Games` mount.
- `zstd:1` + `noatime` everywhere.
- `/persistent` declared `neededForBoot` — dovetails with [[impermanence]].

## Connections
- Up: [[../_index|Modules]]
- Pairs with: [[impermanence]] (the wiped-vs-persistent contract)
- Touches: [[../../concepts/impermanence]]
