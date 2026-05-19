{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    aerc
    notmuch
    msmtp
    isync
    khal
  ];

  home.file.".config/aerc" = {
    source = ../../../.config/aerc;
    recursive = true;
  };
  home.file.".mbsyncrc".source = ../../../.mbsyncrc;
  home.file.".config/khal" = {
    source = ../../../.config/khal;
    recursive = true;
  };
  home.file.".config/notmuch/default/config".source = ../../../.config/notmuch/default/config;

  programs.git.settings = {
    user.name = "mvrozanti";
    user.email = "mvrozanti@hotmail.com";
  };

  programs.gh.gitCredentialHelper.enable = true;
}
