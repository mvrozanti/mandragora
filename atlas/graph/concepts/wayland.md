---
type: concept
tags: [concept, wayland]
---

# Wayland

The display protocol of the system. Hyprland is the compositor; SDDM logs in straight to a Wayland session. There is no X11 fallback by design (non-negotiable #6).

## Touched by

- [[../modules/desktop/hyprland]] — the compositor itself
- [[../modules/desktop/sddm]] — `wayland.enable = true`, `defaultSession = "hyprland"`
- [[../modules/core/graphics]] — NVIDIA Wayland env vars live downstream
- [[../modules/desktop/ydotool]] — Wayland-friendly synthetic input

See: [[nvidia]], [[../../architecture]]
