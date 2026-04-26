---
type: module
layer: core
tags: [module, core, network]
path: modules/core/globals.nix
---

# globals.nix

Networking foundation: hostname, static interface, dnsmasq, DNS plumbing.

## Role
- Sets `networking.hostName = "mandragora"`.
- Static IP on `enp8s0` (192.168.0.27/24); DHCP on Wi-Fi.
- Runs `dnsmasq` with Cloudflare upstreams, hosts injection from a sops template.

## Connections
- Up: [[../_index|Modules]]
- Touches: [[../../concepts/secrets-sops]] (consumes `sops.templates."hosts-oracle"`)
- Sibling: [[security]] (firewall rules layer on top), [[secrets]] (template producer)
