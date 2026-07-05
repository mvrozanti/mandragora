{ pkgs, ... }:

{
  imports = [ ./gpu-menu.nix ];

  systemd.user.services.waybar = {
    Unit.StartLimitIntervalSec = "0";
    Service.RestartSec = "3";
  };

  programs.waybar = {
    enable = true;
    systemd.enable = true;
    style = builtins.readFile ../../snippets/waybar-style.css;
    settings = {
      mainBar = {
        layer = "top";
        position = "bottom";
        height = 40;
        spacing = 6;

        modules-left = [ "hyprland/workspaces" ];
        modules-center = [ ];
        modules-right = [ "group/audio" "group/hardware" "group/network" "group/info" "group/actions" "tray" ];

        "group/audio" = {
          orientation = "horizontal";
          modules = [ "custom/mpd" "custom/mpd-prev" "custom/mpd-toggle" "custom/mpd-next" "custom/mpd-single" "custom/mpd-random" "custom/volume" "bluetooth" ];
        };

        "group/hardware" = {
          orientation = "horizontal";
          modules = [ "disk" "memory" "temperature" "cpu" "custom/gpu" ];
        };

        "group/network" = {
          orientation = "horizontal";
          modules = [ "custom/network-menu" "custom/network" ];
        };

        "group/actions" = {
          orientation = "horizontal";
          modules = [ "custom/monitor" "custom/security" "custom/rss" "custom/notif-menu" "custom/screencap" "custom/clipboard" "custom/powermenu" ];
        };

        "group/info" = {
          orientation = "horizontal";
          modules = [ "custom/weather" "clock" "custom/brightness" ];
        };

        "hyprland/workspaces" = {
          format = "{icon}";
          format-icons = {
            "1" = "";
            "2" = "<span size=\"x-large\"></span>";
            "3" = "";
            "4" = "";
            "5" = "";
            "6" = "";
            "8" = "";
            "9" = "";
            "15" = "";
            "16" = "󰮂";
            "17" = "";
            "18" = "<span size=\"large\"></span>";
            "19" = "<span size=\"large\"></span>";
            "7" = "<span size=\"large\"></span>";
            "10" = "♟";
            "14" = "";
            "23" = "";
            "27" = "";
            "41" = "<span font_family=\"Font Awesome 7 Brands\" size=\"x-large\"></span>";
            "nixos0" = "";
            "nixos1" = "";
            "nixos2" = "";
            "nixos3" = "";
            default = "";
          };
        };

        "custom/mpd" = {
          exec = "~/.config/waybar/scripts/mpd-status.sh";
          return-type = "json";
          on-click = "kitty --class ncmpcpp -o close_on_child_death=yes -e ncmpcpp";
        };

        "custom/mpd-prev" = {
          format = "";
          on-click = "mpc prev";
          tooltip = false;
        };

        "custom/mpd-toggle" = {
          exec = "~/.config/waybar/scripts/mpd-controls.sh toggle";
          return-type = "json";
          on-click = "mpc toggle";
          tooltip = false;
        };

        "custom/mpd-next" = {
          format = "";
          on-click = "mpc next";
          tooltip = false;
        };

        "custom/mpd-single" = {
          exec = "~/.config/waybar/scripts/mpd-controls.sh single";
          return-type = "json";
          on-click = "mpc single";
          tooltip = false;
        };

        "custom/mpd-random" = {
          exec = "~/.config/waybar/scripts/mpd-controls.sh random";
          return-type = "json";
          on-click = "mpc random";
          tooltip = false;
        };

        "custom/volume" = {
          exec = "~/.config/waybar/scripts/volume-ramp.sh";
          return-type = "json";
          # Streaming: script emits on pactl subscribe events; no polling, no signal.
          on-click = "pamixer -t";
          on-scroll-up = "pamixer -i 2";
          on-scroll-down = "pamixer -d 2";
          on-click-right = "pavucontrol";
        };

        "custom/brightness" = {
          exec = "~/.config/waybar/scripts/brightness.sh status";
          interval = 5;
          signal = 12;
          format = "";
          tooltip-format = "Brightness: {}";
          on-click = "~/.config/waybar/scripts/brightness.sh toggle";
          on-scroll-up = "~/.config/waybar/scripts/brightness.sh increase";
          on-scroll-down = "~/.config/waybar/scripts/brightness.sh decrease";
        };

        bluetooth = {
          format = "";
          format-disabled = "";
          format-off = "";
          format-on = "";
          format-connected = "  ";
          format-connected-battery = "  {device_battery_percentage}%  ";
          tooltip-format = "{controller_alias}\t{controller_address}";
          tooltip-format-connected = "{controller_alias}\t{controller_address}\n\n{device_enumerate}";
          tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
          tooltip-format-enumerate-connected-battery = "{device_alias}\t{device_address}\t{device_battery_percentage}%";
          on-click = "${pkgs.bash}/bin/bash ~/.config/waybar/scripts/bluetooth.sh toggle";
          on-click-right = "blueman-manager";
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
        "custom/gpu" = {
          format = "{}";
          exec = "gpu-menu waybar";
          return-type = "json";
          interval = 5;
          tooltip = true;
          on-click = "gpu-menu pick";
        };


        "custom/network" = {
          exec = toString (pkgs.writeShellScript "net-rate" ''
            iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
            if [ -z "$iface" ]; then echo "disconnected"; exit; fi
            rx=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
            tx=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)
            now=$(date +%s)
            prev=/tmp/net-rate-$iface
            if [ -f "$prev" ]; then
              read -r prx ptx pt < "$prev"
              dt=$(( now - pt ))
              if [ "$dt" -gt 0 ]; then
                drx=$(( (rx - prx) / dt ))
                dtx=$(( (tx - ptx) / dt ))
              else drx=0; dtx=0; fi
            else drx=0; dtx=0; fi
            printf "%s %s %s\n" "$rx" "$tx" "$now" > "$prev"
            human() {
              local b=$1
              if   [ "$b" -ge 1073741824 ]; then echo "$(( b / 1073741824 )) GB/s"
              elif [ "$b" -ge 1048576 ];    then echo "$(( b / 1048576 )) MB/s"
              elif [ "$b" -ge 1024 ];       then echo "$(( b / 1024 )) KB/s"
              else echo "$b B/s"; fi
            }
            echo "↑ $(human "$dtx") ↓ $(human "$drx")"
          '');
          interval = 5;
        };

        "custom/network-menu" = {
          exec = toString (pkgs.writeShellScript "net-menu" ''
            iface=$(${pkgs.iproute2}/bin/ip route show default 2>/dev/null | ${pkgs.gawk}/bin/awk '/default/ {print $5; exit}')
            reachable=0
            if [ -n "$iface" ] && ${pkgs.iputils}/bin/ping -c1 -W1 1.1.1.1 >/dev/null 2>&1; then
              reachable=1
            fi
            if [ "$reachable" = 1 ]; then
              printf '{"text":"","class":"online","tooltip":"Online via %s"}\n' "$iface"
            else
              printf '{"text":"󰖪","class":"offline","tooltip":"No internet — click to open wifi manager"}\n'
            fi
          '');
          return-type = "json";
          interval = 5;
          on-click = "kitty --class impala -o close_on_child_death=yes -e impala";
        };

        clock = {
          format = "  {:%H:%M:%S}";
          format-alt = "  {:%Y-%m-%d %H:%M}";
          interval = 1;
          tooltip-format = "<tt>{calendar}</tt>";
        };

        "custom/screencap" = {
          exec = "screencap status";
          return-type = "json";
          interval = 1;
          signal = 11;
          on-click = "capture toggle";
          on-click-right = "capture stop";
        };

        "custom/weather" = {
          exec = "~/.config/waybar/scripts/weather.sh";
          return-type = "json";
          interval = 600;
          on-click = "weather-menu pick";
          on-click-right = "weather-menu pick --refresh";
        };

        tray = {
          spacing = 8;
          show-passive-items = true;
        };

        "custom/clipboard" = {
          format = "";
          tooltip = true;
          tooltip-format = "Clipboard history — left-click to pick, right-click to clear";
          on-click = "clipboard-menu";
          on-click-right = "clipboard-menu clear";
        };

        "custom/notif-menu" = {
          format = "";
          tooltip = true;
          tooltip-format = "Notification history — left-click to browse, right-click to toggle DND";
          on-click = "swaync-client -t -sw";
          on-click-right = "swaync-client -d -sw";
        };

        "custom/monitor" = {
          exec = "monitor-menu waybar";
          return-type = "json";
          interval = 5;
          format = "{}";
          tooltip = true;
          on-click = "nwg-displays";
          on-click-right = "monitor-menu toggle";
          on-click-middle = "monitor-menu pick";
        };

        "custom/security" = {
          exec = "security-menu waybar";
          return-type = "json";
          interval = 300;
          signal = 13;
          format = "{}";
          tooltip = true;
          on-click = "security-menu pick";
          on-click-right = "security-menu rescan";
        };

        "custom/rss" = {
          exec = "rss-menu waybar";
          return-type = "json";
          interval = 60;
          signal = 10;
          format = "{}";
          tooltip = true;
          on-click = "rss-menu pick";
          on-click-right = "rss-menu mark-all-read";
          on-click-middle = "systemctl --user start rss-menu-poll.service";
        };

        "custom/powermenu" = {
          format = "";
          tooltip = false;
          on-click = "rofi-power-menu";
        };
      };
    };
  };
}
