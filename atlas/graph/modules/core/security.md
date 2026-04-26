---
type: module
layer: core
tags: [module, core, security, network]
path: modules/core/security.nix
---

# security.nix

Firewall + DNS-over-TLS. The defensive perimeter.

## Role
- `nftables` firewall with narrow allowlist (3000, 9090, 9100; 6600 on `enp8s0` for [[../user/services|mpd]]).
- `systemd-resolved` with DoT (Cloudflare primary, Quad9 fallback), DNSSEC allow-downgrade.
- NetworkManager → resolved.

## Connections
- Up: [[../_index|Modules]]
- Pairs with: [[globals]] (where the interfaces live), [[monitoring]] (opens the Prometheus ports)
- Touches: [[../../concepts/declarative-supremacy]]
