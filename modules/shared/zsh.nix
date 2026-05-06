{ config, lib, ... }:

let cfg = config.mandragora; in {
  config = lib.mkMerge [
    {
      programs.zsh.enable = true;
    }

    (lib.mkIf (cfg.profile == "live") {
      programs.zsh.shellInit = ''
        export PS1='%F{cyan}mandragora-live%f:%~%# '
      '';
    })
  ];
}
