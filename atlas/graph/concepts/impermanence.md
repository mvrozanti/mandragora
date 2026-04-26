---
type: concept
tags: [concept, impermanence, storage]
---

# Impermanence

The root filesystem is wiped on every boot. Only `/nix`, `/persistent`, and `/home/m` (bind-mounted from `/persistent/home/m`) survive (non-negotiable #5).

Anything that wants state must declare a persistent directory or a bind-mount. Nothing else.

## Touched by

- [[../modules/core/impermanence]] — the contract itself
- [[../modules/core/storage]] — btrfs subvols underneath
- [[../modules/core/persistence-vms]] — libvirt + swtpm survive
- [[../modules/core/secrets]] — age key lives at `/persistent/secrets/keys.txt`
- [[../modules/core/ai-local]] — Ollama state at `/persistent/var/lib/private/ollama`

See: [[../../architecture]], [[../../non-negotiables]]
