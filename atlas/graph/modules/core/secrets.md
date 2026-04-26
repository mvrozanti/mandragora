---
type: module
layer: core
tags: [module, core, secrets, sops]
path: modules/core/secrets.nix
---

# secrets.nix

sops-nix with age. Every secret enters the system through here.

## Role
- `defaultSopsFile = ../../secrets/secrets.yaml`; age key at `/persistent/secrets/keys.txt`.
- Declares secrets: `user/password` (`neededForUsers`), `weather/api_key`, `oracle/ip`, plus more.
- Wraps [[../../scripts/oracle-hosts-inject]] as a `writeShellScript` for activation.
- Renders the `hosts-oracle` template that [[globals]]'s dnsmasq consumes.

## Connections
- Up: [[../_index|Modules]]
- Consumed by: [[globals]] (hosts template), [[../user/waybar]] (weather API key), [[../desktop/seafile]] (auth token, gated)
- Scripts: [[../../scripts/oracle-hosts-inject]]
- Touches: [[../../concepts/secrets-sops]], [[../../concepts/impermanence]] (age key location)
