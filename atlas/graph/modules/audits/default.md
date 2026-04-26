---
type: module
layer: audits
tags: [module, audits]
path: modules/audits/default.nix
---

# audits/default.nix

Activates the audit scripts. Health-check on boot; strays watcher in user-space.

## Role
- Wraps [[../../scripts/health-check]] and [[../../scripts/strays]] as activation scripts / one-shots.

## Connections
- Up: [[../_index|Modules]]
- Scripts: [[../../scripts/health-check]], [[../../scripts/strays]]
- Touches: [[../../concepts/declarative-supremacy]]
