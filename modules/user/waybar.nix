{ config, pkgs, ... }:

{
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    style = builtins.readFile ../../snippets/waybar-style.css;
    settings = {
      mainBar = {
        layer = "top";
        position = "bottom";
        height = 40;
        spacing = 0;

        modules-left = [ "hyprland/workspaces" ];
        modules-center = [ "mpd" ];
        modules-right = [ "custom/obs" "custom/volume" "disk" "memory" "temperature" "cpu" "network" "custom/weather" "clock" "tray" ];

        "hyprland/workspaces" = {
          format = "{icon}";
          format-icons = {
            "1" = "";
            "2" = "";
            "3" = "";
            "4" = "";
            "5" = "";
            "6" = "";
            "8" = "";
            "9" = "";
            "15" = "";
            "17" = "";
            "18" = "";
            "60" = "<span size=\"large\"></span>";
            "27" = "";
            "41" = "";
            default = "";
          };
        };

        mpd = {
          format = "  {title} {stateIcon}";
          format-stopped = "";
          format-disconnected = "";
          state-icons = {
            playing = "";
            paused = "";
          };
          tooltip-format = "{artist} — {album} ({elapsedTime:%M:%S}/{totalTime:%M:%S})";
          on-click = "mpc toggle";
          on-click-right = "kitty --class ncmpcpp -o close_on_child_death=yes -e ncmpcpp";
          on-scroll-up = "mpc next";
          on-scroll-down = "mpc prev";
        };

        "custom/volume" = {
          exec = "~/.config/waybar/scripts/volume-ramp.sh";
          return-type = "json";
          format = "{}";
          interval = 1;
          on-click = "pamixer -t";
          on-scroll-up = "pamixer -i 2";
          on-scroll-down = "pamixer -d 2";
          on-click-right = "pavucontrol";
        };

        disk = {
          format = "  {percentage_free}%";
          path = "/";
          interval = 30;
        };

        memory = {
          format = " {percentage}%";
          interval = 5;
          tooltip-format = "{used:0.1f}G / {total:0.1f}G";
        };

        temperature = {
          critical-threshold = 85;
          format = " {temperatureC}°";
          hwmon-path-abs = "/sys/devices/pci0000:00/0000:00:18.3/hwmon";
          input-filename = "temp1_input";
        };

        cpu = {
          format = "  {usage}%";
          interval = 5;
        };

        network = {
          format-ethernet = "↑ {bandwidthUpBits} ↓ {bandwidthDownBits}";
          format-disconnected = "disconnected";
          tooltip-format = "{ifname}: {ipaddr}/{cidr}";
          interval = 2;
        };

        clock = {
          format = "  {:%H:%M:%S}";
          format-alt = "  {:%Y-%m-%d %H:%M}";
          interval = 1;
          tooltip-format = "<tt>{calendar}</tt>";
        };

        "custom/obs" = {
          exec = "~/.config/waybar/scripts/obs-recording.sh";
          return-type = "json";
          interval = 3;
        };

        "custom/weather" = {
          exec = "~/.config/waybar/scripts/weather.sh";
          return-type = "json";
          interval = 600;
        };

        tray = {
          spacing = 8;
        };
      };
    };
  };
}
