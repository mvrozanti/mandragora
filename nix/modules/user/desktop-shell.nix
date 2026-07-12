{ pkgs, ... }:

{
    services.udiskie = {
    enable = true;
    automount = true;
    notify = true;
    tray = "auto";
  };

  wayland.windowManager.hyprland = {
    enable = true;
    settings = {
      exec-once = [
        "awww-daemon"
        "restore-theme"
        "wl-paste --watch cliphist store"
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
        "kdeconnect-indicator"
        "blueman-applet"
      ];
    };
    extraConfig = builtins.readFile ../../../.config/hypr/hyprland.conf;
  };

  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        disable_loading_bar = true;
        hide_cursor = true;
      };
      background = [{
        monitor = "";
        color = "rgb(282c34)";
        blur_passes = 2;
        blur_size = 7;
      }];
      input-field = [{
        monitor = "";
        size = "300, 50";
        position = "0, -80";
        halign = "center";
        valign = "center";
        outline_thickness = 2;
        outer_color = "rgb(61afef)";
        inner_color = "rgb(2c313c)";
        font_color = "rgb(abb2bf)";
        placeholder_text = "";
        dots_size = 0.33;
        dots_spacing = 0.15;
        dots_center = true;
      }];
      label = [{
        monitor = "";
        text = "$TIME";
        color = "rgb(abb2bf)";
        font_size = 64;
        font_family = "Iosevka Nerd Font Mono";
        position = "0, 80";
        halign = "center";
        valign = "center";
      }];
    };
  };

  services.swaync = {
    enable = true;
    style = ../../../.config/swaync/style.css;
    settings = {
      positionX = "right";
      positionY = "bottom";
      layer = "overlay";
      control-center-layer = "top";
      cssPriority = "user";
      control-center-width = 420;
      control-center-height = -1;
      control-center-margin-bottom = 0;
      control-center-margin-right = 12;
      notification-window-width = 420;
      notification-icon-size = 48;
      notification-body-image-height = 160;
      notification-body-image-width = 300;
      timeout = 8;
      timeout-low = 5;
      timeout-critical = 0;
      fit-to-screen = false;
      hide-on-clear = true;
      hide-on-action = true;
      keyboard-shortcuts = true;
      script-fail-notify = true;
      widgets = [ "title" "dnd" "notifications" ];
      widget-config = {
        title = {
          text = "Notifications";
          clear-all-button = true;
          button-text = "Clear all";
        };
        dnd = { text = "Do not disturb"; };
        notifications = { vexpand = true; };
      };
    };
  };
}
