---
type: module
layer: core
tags: [module, core, monitoring]
path: modules/core/monitoring.nix
---

# monitoring.nix

Prometheus + node exporter + custom exporters + a hand-rolled Grafana dashboard.

## Role
- Scrapes node-exporter, NVIDIA GPU metrics, and the custom [[../../packages/du-exporter]] (top-N largest dirs).
- Embeds the Grafana dashboard JSON declaratively.

## Connections
- Up: [[../_index|Modules]]
- Pairs with: [[security]] (firewall opens 3000/9090/9100), [[graphics]] (GPU metrics)
- Packages: [[../../packages/du-exporter]]
- Touches: [[../../concepts/declarative-supremacy]]
