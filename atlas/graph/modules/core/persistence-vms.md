---
type: module
layer: core
tags: [module, core, virtualization, impermanence]
path: modules/core/persistence-vms.nix
---

# persistence-vms.nix

Pins libvirt + swtpm state into `/persistent` so VMs survive root wipes.

## Role
- `/var/lib/libvirt`, `/var/lib/swtpm` declared persistent.

## Connections
- Up: [[../_index|Modules]]
- Pairs with: [[vm]] (consumer), [[impermanence]] (the contract this honors)
- Touches: [[../../concepts/impermanence]]
