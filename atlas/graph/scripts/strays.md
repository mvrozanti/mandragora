---
type: script
tags: [script, audit]
path: modules/audits/strays.sh
---

# strays

Find files in `/etc/nixos/mandragora` that aren't tracked by git — orphans, untagged work-in-progress, leftover artifacts.

Wrapped by: [[../modules/audits/default]]
