{ config, lib, ... }:

let cfg = config.mandragora; in {
  config = lib.mkMerge [
    {
      programs.zsh.enable = true;
    }

    (lib.mkIf (cfg.profile == "live") {
      programs.zsh.shellInit = builtins.readFile ../../snippets/zsh-live-prompt.zsh;
    })
  ];
}
