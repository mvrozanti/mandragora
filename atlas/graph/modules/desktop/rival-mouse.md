---
type: module
layer: desktop
tags: [module, desktop, input]
path: modules/desktop/rival-mouse.nix
---

# rival-mouse.nix

A udev rule for the SteelSeries Rival to keep USB power-management on.

## Role
- One `udev.extraRules` line matching the SteelSeries vendor/product IDs.

## Connections
- Up: [[../_index|Modules]]
- Pairs with: [[keyd]], [[ydotool]] (input layer siblings)
