---
type: module
layer: user
tags: [module, user, home-manager]
path: modules/user/home-manager.nix
---

# home-manager.nix

The thin shim that mounts home-manager onto user `m` and points it at [[home]].

## Role
- `useGlobalPkgs`, `useUserPackages`.
- `users.m = import ./home.nix`.
- Forwards `inputs` via `extraSpecialArgs`.

## Connections
- Up: [[../_index|Modules]]
- Pairs with: [[home]] (the actual user config)
