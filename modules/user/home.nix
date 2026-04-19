{ config, pkgs, ... }:

let
  smart-launch = pkgs.writeShellScript "smart-launch" (builtins.readFile ../../snippets/smart-launch.sh);
in

{
  imports = [
    ./waybar.nix
  ];

  home.username = "m";
  home.homeDirectory = "/home/m";
  home.stateVersion = "24.05";

  home.file.".XCompose".source = ../../snippets/XCompose;

  programs.home-manager.enable = true;

  programs.kitty = {
    enable = true;
    settings = {
      font_family = "IosevkaTerm Nerd Font Mono";
    };
  };

  programs.firefox.enable = true;

  home.packages = [
    (pkgs.writeShellScriptBin "mandragora-switch" (builtins.readFile ../../snippets/mandragora-switch.sh))
  ];

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    history = {
      size = 50000;
      save = 50000;
      path = "${config.home.homeDirectory}/.local/state/zsh/history";
      ignoreDups = true;
      share = true;
    };
    shellAliases = {
      switch = "mandragora-switch";
      ll = "ls -lah";
      la = "ls -A";
      nix-shell = "nix shell nixpkgs#";
      rebuild = "mandragora-switch";
    };
    initContent = builtins.readFile ../../snippets/zshrc.zsh;
  };

  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        hide_cursor = true;
        grace = 0;
      };
      background = [{
        monitor = "";
        path = "screenshot";
        blur_passes = 3;
        blur_size = 7;
      }];
      input-field = [{
        monitor = "";
        size = "200, 50";
        outline_thickness = 3;
        outer_color = "rgb(cba6f7)";
        inner_color = "rgb(20, 20, 20)";
        font_color = "rgb(220, 220, 220)";
        fade_on_empty = true;
        placeholder_text = "";
        position = "0, -80";
        halign = "center";
        valign = "center";
      }];
    };
  };

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "hyprlock";
        before_sleep_cmd = "hyprlock";
        after_sleep_cmd = "hyprctl dispatch dpms on";
        ignore_dbus_inhibit = false;
      };
      listener = [
        {
          timeout = 300;
          on-timeout = "hyprlock";
        }
        {
          timeout = 600;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
      ];
    };
  };

  programs.ncmpcpp = {
    enable = true;
    settings = {
      mpd_connection_timeout = "5";
      progressbar_look = "=>-";
      user_interface = "alternative";
    };
  };

  services.mpd = {
    enable = true;
    musicDirectory = "${config.home.homeDirectory}/Music";
    extraConfig = builtins.readFile ../../snippets/mpd.conf;
  };

  wayland.windowManager.hyprland = {
    enable = true;

    settings = {
      monitor = [ ", preferred, auto, 1" ];

      general = {
        border_size = 2;
        gaps_in = 6;
        gaps_out = 12;
        layout = "dwindle";
        "col.active_border" = "rgb(cba6f7)";
        "col.inactive_border" = "rgb(313244)";
      };

      input = {
        kb_layout = "us";
        kb_variant = "intl";
        repeat_delay = 200;
        repeat_rate = 30;
        follow_mouse = 1;
        sensitivity = 0;
      };

      dwindle = {
        pseudotile = true;
        preserve_split = true;
      };

      decoration = {
        rounding = 8;
        blur = {
          enabled = true;
          size = 5;
          passes = 2;
        };
        shadow = {
          enabled = true;
          range = 10;
        };
      };

      animations = {
        enabled = true;
        bezier = [ "snappy, 0.05, 0.9, 0.1, 1.0" ];
        animation = [
          "windows, 1, 4, snappy"
          "windowsOut, 1, 4, snappy"
          "fade, 1, 4, snappy"
          "workspaces, 1, 3, snappy"
        ];
      };

      "exec-once" = [ "waybar" ];

      bind = [
        "SUPER, Return, exec, kitty"
        "SUPER, Q, killactive,"
        "SUPER, F, fullscreen,"
        "SUPER, space, togglefloating,"
        "SUPER, E, togglesplit,"
        "SUPER, S, pin,"
        "SUPER, R, exec, rofi -show drun"

        "SUPER, 1, exec, ${smart-launch} firefox firefox"
        "SUPER, 2, exec, ${smart-launch} lf 'kitty --class lf -e lf'"
        "SUPER, 3, exec, kitty"
        "SUPER, 4, exec, ${smart-launch} neomutt 'kitty --class neomutt -e neomutt'"
        "SUPER, 5, exec, ${smart-launch} org.telegram.desktop telegram-desktop"
        "SUPER, W, exec, ${smart-launch} ncmpcpp 'kitty --class ncmpcpp -e ncmpcpp'"
        "SUPER, O, exec, ${smart-launch} obsidian obsidian"
        "SUPER, X, exec, ${smart-launch} discord discord"

        "SUPER, H, movefocus, l"
        "SUPER, J, movefocus, d"
        "SUPER, K, movefocus, u"
        "SUPER, L, movefocus, r"

        "SUPER SHIFT, H, movewindow, l"
        "SUPER SHIFT, J, movewindow, d"
        "SUPER SHIFT, K, movewindow, u"
        "SUPER SHIFT, L, movewindow, r"

        "SUPER CTRL, H, resizeactive, -20 0"
        "SUPER CTRL, J, resizeactive, 0 20"
        "SUPER CTRL, K, resizeactive, 0 -20"
        "SUPER CTRL, L, resizeactive, 20 0"

        "SUPER SHIFT, A, workspace, e-1"
        "SUPER SHIFT, S, workspace, e+1"
        "ALT, Tab, workspace, previous"
        "SUPER, grave, workspace, e+1"

        ", XF86AudioRaiseVolume, exec, pamixer -i 5"
        ", XF86AudioLowerVolume, exec, pamixer -d 5"
        ", XF86AudioMute, exec, pamixer -t"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl previous"

        ''SUPER, Print, exec, grim -g "$(slurp)" - | wl-copy''
        "SUPER, Home, exec, hyprlock"
        "SUPER, BackSpace, exec, hyprctl dispatch dpms off"
        "SUPER, F5, exec, kitty --class rebuild -e mandragora-switch"
      ];

      bindm = [
        "SUPER, mouse:272, movewindow"
        "SUPER, mouse:273, resizewindow"
      ];

      windowrule = [
        "float, class:^(rebuild)$"
        "size 900 500, class:^(rebuild)$"
        "center, class:^(rebuild)$"
        "workspace 2, class:^(lf)$"
        "workspace 4, class:^(neomutt)$"
        "workspace 5, class:^(org.telegram.desktop)$"
        "workspace 8, class:^(jetbrains-.*)$"
        "workspace 8, class:^(code)$"
        "workspace 9, class:^(Slack)$"
        "float, class:^(mpv)$"
      ];
    };
  };
}
