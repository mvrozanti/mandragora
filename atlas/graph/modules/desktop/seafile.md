---
type: module
layer: desktop
tags: [module, desktop, sync]
path: modules/desktop/seafile.nix
---

# seafile.nix

Self-hosted file sync client. Currently opt-in (gated by `services.mandragora-seafile.enable`).

## Role
- Defines a custom `mandragora-seafile` enable flag.
- Ships `seafile-client` only when enabled.
- Will consume a `seafile/auth-token` from [[../core/secrets]] when fully wired.

## Connections
- Up: [[../_index|Modules]]
- Pairs with: [[../core/secrets]] (auth token, planned)
- Touches: [[../../concepts/secrets-sops]]
