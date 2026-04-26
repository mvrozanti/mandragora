---
type: module
layer: user
tags: [module, user, services, ai, nvidia]
path: modules/user/bots.nix
---

# bots.nix

User-level Telegram bot service. Watches `/dev/nvidia0` for image-generation work.

## Role
- Imports [[../../packages/bot-python]] for the Python env.
- Defines a systemd user service tied to the NVIDIA device.

## Connections
- Up: [[../_index|Modules]]
- Imported by: [[home]]
- Packages: [[../../packages/bot-python]]
- Pairs with: [[../core/graphics]] (consumes GPU), [[../core/ai-local]] (AI sibling)
- Touches: [[../../concepts/ai-stack]], [[../../concepts/nvidia]]
