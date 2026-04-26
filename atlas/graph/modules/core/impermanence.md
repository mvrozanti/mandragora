---
type: module
layer: core
tags: [module, core, impermanence, storage]
path: modules/core/impermanence.nix
---

# impermanence.nix

The root-wipe contract: only `/nix`, `/persistent`, and `/home/m` (bind-mount) survive a reboot.

## Role
- Declares persistent dirs: `/var/log`, `/var/lib/nixos`, NetworkManager system-connections, user home.
- Conditionally persists `/persistent/var/lib/private/ollama` when [[ai-local]] is enabled.
- Symlinks `/etc/machine-id` and `/etc/nixos/mandragora` from `/persistent`.

## Connections
- Up: [[../_index|Modules]]
- Pairs with: [[storage]] (subvols), [[ai-local]] (Ollama state), [[secrets]] (age key at `/persistent/secrets/keys.txt`), [[persistence-vms]] (VM state)
- Touches: [[../../concepts/impermanence]]
