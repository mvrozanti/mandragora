{ config, pkgs, ... }:

{
  programs.waybar = {
    enable = true;
    style = builtins.readFile ../../snippets/waybar-style.css;
    settings = {
      mainBar = {
        layer = "top";
        position = "bottom";
        height = 34;
        spacing = 0;

        modules-left = [ "hyprland/workspaces" ];
        modules-center = [ "mpd" ];
        modules-right = [ "privacy" "idle_inhibitor" "pulseaudio" "disk" "memory" "temperature" "cpu" "network" "clock" "tray" ];

        "hyprland/workspaces" = {
          format = "{icon}";
          format-icons = {
            "1" = "";
            "2" = "";
            "3" = "";
            "4" = "";
            "5" = "";
            "6" = "";
            "8" = "";
            "9" = "";
            "15" = "";
            "17" = "";
            "18" = "";
            "27" = "";
            "41" = "";
            default = "";
          };
          persistent-workspaces = {
            "1" = [];
            "2" = [];
            "3" = [];
          };
        };

        mpd = {
          format = "  {title} {stateIcon}";
          format-stopped = "";
          format-disconnected = "";
          state-icons = {
            playing = "";
            paused = "";
          };
          tooltip-format = "{artist} — {album} ({elapsedTime:%M:%S}/{totalTime:%M:%S})";
          on-click = "mpc toggle";
          on-click-right = "kitty --class ncmpcpp -o close_on_child_death=yes -e ncmpcpp";
          on-scroll-up = "mpc next";
          on-scroll-down = "mpc prev";
        };

        pulseaudio = {
          format = "{icon} {volume}%";
          format-muted = " muted";
          format-icons = {
            default = [ "" "" "" ];
          };
          on-click = "pamixer -t";
          on-scroll-up = "pamixer -i 2";
          on-scroll-down = "pamixer -d 2";
          on-click-right = "pavucontrol";
        };

        disk = {
          format = " {percentage_free}%";
          path = "/";
          interval = 30;
        };

        memory = {
          format = " {percentage}%";
          interval = 5;
          tooltip-format = "{used:0.1f}G / {total:0.1f}G";
        };

        temperature = {
          critical-threshold = 85;
          format = " {temperatureC}°";
          hwmon-path-abs = "/sys/devices/pci0000:00/0000:00:18.3/hwmon";
          input-filename = "temp1_input";
        };

        cpu = {
          format = " {usage}%";
          interval = 5;
        };

        network = {
          format-ethernet = "↑{bandwidthUpBits} ↓{bandwidthDownBits}";
          format-disconnected = "disconnected";
          tooltip-format = "{ifname}: {ipaddr}/{cidr}";
          interval = 2;
        };

        clock = {
          format = " {:%H:%M:%S}";
          format-alt = " {:%Y-%m-%d %H:%M}";
          interval = 1;
          tooltip-format = "<tt>{calendar}</tt>";
        };

        idle_inhibitor = {
          format = "{icon}";
          format-icons = {
            activated = "󰒳";
            deactivated = "󰒲";
          };
          tooltip-format-activated = "Idle inhibited";
          tooltip-format-deactivated = "Idle allowed";
        };

        privacy = {
          icon-spacing = 4;
          icon-size = 14;
          transition-duration = 250;
          modules = [
            { type = "screenshare"; tooltip = true; tooltip-icon-size = 24; }
            { type = "audio-in"; tooltip = true; tooltip-icon-size = 24; }
          ];
        };

        tray = {
          spacing = 8;
        };
      };
    };
  };
}
