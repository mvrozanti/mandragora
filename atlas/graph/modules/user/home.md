---
type: module
layer: user
tags: [module, user, packages]
path: modules/user/home.nix
---

# home.nix

The user-space gravity well — packages, env, and ~50 `writeShellScriptBin` wrappers around `.local/bin/`.

## Role
- Imports siblings: [[zsh]], [[tmux]], [[lf]], [[services]], [[bots]], [[waybar]], [[minecraft-user|minecraft]], [[skills]].
- Wraps every workflow script ([[../../scripts/mandragora-switch]], [[../../scripts/mandragora-commit-push]], [[../../scripts/mandragora-diff]], [[../../scripts/cycle-audio-output]], [[../../scripts/capture]], [[../../scripts/screenshot-window]], [[../../scripts/gap-adjust]], [[../../scripts/blur-adjust]], …) as a binary.
- Reads `.config/zsh/zshrc.zsh` and `.config/zsh/p10k.zsh`.

## Connections
- Up: [[../_index|Modules]]
- Imported by: [[home-manager]]
- Imports siblings: [[zsh]], [[tmux]], [[lf]], [[services]], [[bots]], [[waybar]], [[minecraft-user|minecraft]], [[skills]]
- Configs: [[../../configs/zsh]]
- Touches: [[../../concepts/language-purity]], [[../../concepts/rebuild-workflow]], [[../../concepts/agent-worktrees]]
