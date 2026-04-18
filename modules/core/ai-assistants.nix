{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.mandragora.ai-assistants;
in
{
  options.mandragora.ai-assistants = {
    enable = mkEnableOption "Unified AI assistants configuration symlinks";
  };

  config = mkIf cfg.enable {
    home.file = {
      ".AGENTS.md".source = ../../AGENTS.md;
    };

    home.activation.linkAiAssistants = lib.hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD ln -sf ${config.home.homeDirectory}/.AGENTS.md ${config.home.homeDirectory}/.claude/CLAUDE.md
      $DRY_RUN_CMD ln -sf ${config.home.homeDirectory}/.AGENTS.md ${config.home.homeDirectory}/.qwen/QWEN.md
      $DRY_RUN_CMD ln -sf ${config.home.homeDirectory}/.AGENTS.md ${config.home.homeDirectory}/.gemini/GEMINI.md
    '';
  };
}
