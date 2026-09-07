{ pkgs, ... }:

{
  services.espanso = {
    enable = true;
    package = pkgs.espanso-wayland;
  };

  home-manager.users.m.home.file.".config/espanso" = {
    source = ../../../.config/espanso;
    recursive = true;
  };
}
