{ config, pkgs, ... }:
{
  imports = [
    ./waybar.nix
  ];

  home.username = "m";
  home.homeDirectory = "/home/m";

  home.stateVersion = "24.05";

  programs.home-manager.enable = true;

  # Kitty Terminal Configuration
  programs.kitty = {
    enable = true;
    settings = {
      font_family = "IosevkaTerm Nerd Font Mono";
      # Colors will be managed dynamically via pywal
    };
  };

  # Firefox
  programs.firefox = {
    enable = true;
  };
}
