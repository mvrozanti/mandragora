---
type: module
layer: core
tags: [module, core, boot]
path: modules/core/boot.nix
---

# boot.nix

systemd-boot, EFI, kernel selection, and a few hardware quirk knobs.

## Role
- `systemd-boot` + `canTouchEfiVariables`.
- `linuxPackages_zen` kernel.
- Quirk params: `usbcore.autosuspend=-1`, `acpi_enforce_resources=lax`.
- Loads `i2c_piix4` / `i2c_dev` (consumed by [[../desktop/openrgb|openrgb]] for RGB I²C).

## Connections
- Up: [[../_index|Modules]]
- Pairs with: [[graphics]] (loads `nvidia*` kernel modules), [[storage]] (root fs)
- Touches: [[../../concepts/declarative-supremacy]]
