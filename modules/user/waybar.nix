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
        spacing = 6;

        modules-left = [ "hyprland/workspaces" ];
        modules-center = [ "custom/mpd" ];
        modules-right = [ "custom/screencap" "custom/volume" "disk" "memory" "temperature" "cpu" "custom/network" "custom/weather" "clock" "custom/powermenu" "tray" ];

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
            "9" = "";
            "15" = "";
            "17" = "";
            "18" = "";
            "7" = "<span size=\"large\"></span>";
            "10" = "♟";
            "23" = "";
            "27" = "";
            "41" = "";
            default = "";
          };
        };

        "custom/mpd" = {
          exec = "~/.config/waybar/scripts/mpd-status.sh";
          return-type = "json";
          on-click = "mpc toggle";
          on-click-right = "kitty --class ncmpcpp -o close_on_child_death=yes -e ncmpcpp";
          on-scroll-up = "mpc next";
          on-scroll-down = "mpc prev";
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

        clock = {
          format = "  {:%H:%M:%S}";
          format-alt = "  {:%Y-%m-%d %H:%M}";
          interval = 1;
          tooltip-format = "<tt>{calendar}</tt>";
        };

        "custom/screencap" = {
          exec = "~/.local/bin/screencap status";
          return-type = "json";
          interval = 2;
          signal = 11;
          on-click = "~/.local/bin/capture toggle";
          on-click-right = "~/.local/bin/capture stop";
        };

        "custom/weather" = {
          exec = "~/.config/waybar/scripts/weather.sh";
          return-type = "json";
          interval = 600;
        };

        tray = {
          spacing = 8;
          show-passive-items = true;
        };

        "custom/powermenu" = {
          format = "";
          tooltip = false;
          on-click = "powermenu-toggle";
        };
      };
    };
  };
}
