---
type: module
layer: desktop
tags: [module, desktop, lighting]
path: modules/desktop/openrgb.nix
---

# openrgb.nix

Generic RGB device control — opt-in only. Disabled at boot to avoid clobbering [[keyledsd]].

## Role
- `services.hardware.openrgb` enabled but `wantedBy` forced empty (manual start).
- Reason: openrgb's HID probe corrupts keyleds' feature discovery on the Logitech G Pro keyboard.
- Loads `i2c-dev` for motherboard/RAM RGB control.

## Connections
- Up: [[../_index|Modules]]
- Pairs with: [[keyledsd]] (mutually exclusive on shared HID), [[../core/boot]] (`i2c_dev` kernel module)
