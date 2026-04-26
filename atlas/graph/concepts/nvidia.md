---
type: concept
tags: [concept, nvidia, hardware]
---

# NVIDIA

RTX 5070 Ti 16 GB on beta 570.x drivers. **Wayland-only** — no X11 fallback.

The whole system is built around the assumption that NVIDIA + Wayland works. [[../modules/core/graphics]] declares `mandragora.hardware.gpu.vramGB = 16`, and other modules read it as a gate.

## Touched by

- [[../modules/core/graphics]] — driver + VRAM declaration
- [[../modules/core/ai-local]] — asserts `vramGB >= 16` before enabling agentic stack
- [[../modules/core/monitoring]] — NVIDIA GPU metrics scrape
- [[../modules/desktop/hyprland]] — `LIBVA_DRIVER_NAME`, `GBM_BACKEND`, `__GLX_VENDOR_LIBRARY_NAME=nvidia` env vars
- [[../modules/desktop/steam]] — gaming consumer
- [[../modules/user/bots]] — watches `/dev/nvidia0` for image-gen workload

See: [[../../architecture]], [[../../hardware]]
