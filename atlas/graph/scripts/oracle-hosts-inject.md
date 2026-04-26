---
type: script
tags: [script, secrets, network]
path: .local/bin/oracle-hosts-inject.sh
---

# oracle-hosts-inject

Pulls the oracle node's IP from sops-decoded `oracle/ip` and renders the `hosts-oracle` template that [[../modules/core/globals|dnsmasq]] picks up.

Wrapped by: [[../modules/core/secrets]] (as a `pkgs.writeShellScript`)
Touches: [[../concepts/secrets-sops]]
