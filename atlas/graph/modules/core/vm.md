---
type: module
layer: core
tags: [module, core, virtualization]
path: modules/core/vm.nix
---

# vm.nix

Virtualization scaffolding — currently disabled but kept reachable.

## Role
- `libvirtd` and `virt-manager` declared but not enabled.
- Ships `quickemu` / `quickgui` binaries for ad-hoc VMs.

## Connections
- Up: [[../_index|Modules]]
- Pairs with: [[persistence-vms]] (where state lives when this is on)
