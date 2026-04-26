---
type: concept
tags: [concept, philosophy]
---

# Language purity

Non-Nix code (shell, Python, CSS, Lua, INI) lives in XDG-mirrored directories at the repo root and is referenced from `.nix` files via `builtins.readFile` or `pkgs.writeShellScript` (non-negotiable #2). Never `extraConfig = "…"` string blocks inside `.nix`.

The result: `.local/bin/*.sh` is editable as shell, `.config/<app>/*` is editable as the app's native format, and Nix is the glue.

## Touched by

- [[../modules/user/home]] — wraps ~50 scripts as bins
- [[../modules/user/zsh]], [[../modules/user/tmux]], [[../modules/user/lf]], [[../modules/user/services]], [[../modules/user/waybar]] — read configs in
- [[../modules/desktop/hyprland]], [[../modules/desktop/keyledsd]] — read scripts/configs in
- [[../modules/core/secrets]], [[../modules/core/ai-local]] — wrap scripts as derivations

See: [[declarative-supremacy]], [[../../non-negotiables]]
