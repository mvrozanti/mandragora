{ config, pkgs, ... }:

{
  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 30;
        modules-left = [ "hyprland/workspaces" ];
        modules-center = [ "hyprland/window" ];
        modules-right = [ "network" "pulseaudio" "clock" ];
        # Dotfile Translation: Add converted polybar logic here
      };
    };
    # CSS styling would be injected or included here
    # style = "...";
  };
}
