{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    aerc
    notmuch
    msmtp
    isync
    khal
  ];

  home.file.".config/aerc" = {
    source = ../../.config/aerc;
    recursive = true;
  };
  home.file.".config/khal" = {
    source = ../../.config/khal;
    recursive = true;
  };
  home.file.".config/notmuch/default/config".text = ''
    [database]
    path=${config.home.homeDirectory}/.local/share/mail

    [user]
    name=Marcelo Vironda Rozanti
    primary_email=mvrozanti@hotmail.com

    [new]
    tags=unread;inbox;
    ignore=

    [search]
    exclude_tags=deleted;spam;

    [maildir]
    synchronize_flags=true
  '';

  programs.git.settings = {
    user.name = "mvrozanti";
    user.email = "mvrozanti@hotmail.com";
  };

  programs.gh.gitCredentialHelper.enable = true;
}
