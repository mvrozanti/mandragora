---
type: package
tags: [package, overlay]
path: pkgs/overlays.nix
---

# overlays.nix

The nixpkgs overlay registrar. Imported first by every host so all custom packages are visible as `pkgs.<name>`.

Consumed by: every host (`hosts/*/default.nix` imports it).
