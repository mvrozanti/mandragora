_:

{
  services.udiskie = {
    enable = true;
    automount = true;
    notify = true;
    tray = "auto";
  };

  wayland.windowManager.hyprland = {
    enable = true;
    configType = "hyprlang";
    settings = {
      exec-once = [
        "restore-theme"
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
      background = [
        {
          monitor = "";
          color = "rgb(282c34)";
          blur_passes = 2;
          blur_size = 7;
        }
      ];
      input-field = [
        {
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
        }
      ];
      label = [
        {
          monitor = "";
          text = "$TIME";
          color = "rgb(abb2bf)";
          font_size = 64;
          font_family = "Iosevka Nerd Font Mono";
          position = "0, 80";
          halign = "center";
          valign = "center";
        }
      ];
    };
  };
}
