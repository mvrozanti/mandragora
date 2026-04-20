{ config, pkgs, ... }:

{
  services.mpd = {
    enable = true;
    musicDirectory = "~/Music";
    extraConfig = builtins.readFile ../../.config/mpd/mpd.conf;
  };

  # Transmission Daemon Service
  systemd.user.services.transmission = {
    Unit = {
      Description = "Transmission Daemon (user)";
      After = [ "network.target" ];
    };
    Service = {
      ExecStart = "${pkgs.transmission_4}/bin/transmission-daemon --config-dir %h/.config/transmission --foreground";
      ExecStop = "${pkgs.transmission_4}/bin/transmission-remote --exit";
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # mbsync Hotmail Sync Service
  systemd.user.services.mbsync-hotmail = {
    Unit = {
      Description = "Sync Hotmail with mbsync";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      Environment = "GPG_TTY=/dev/tty";
      ExecStart = pkgs.writeShellScript "mbsync-hotmail-script" ''
        ${pkgs.isync}/bin/mbsync mvrozanti@hotmail.com
        
        # Simple notification logic inspired by mbsync-notify.sh
        # (Assuming the user has a working mbsync config for 'hotmail')
        sync_output=/run/current-system/sw/bin/bash: line 2: ${pkgs.isync}/bin/mbsync: No such file or directory
        
        # Extract counts (rough approximation of the logic in mbsync-notify.sh)
        # Note: This might need tuning based on actual mbsync output
        slave_count=$(grep 'Inbox' -A6 <<< "$sync_output" | grep -E '^slave' | cut -d',' -f1 | tr -cd '[[:digit:]]' || echo 0)
        master_count=$(grep 'Inbox' -A6 <<< "$sync_output" | grep -E '^master' | cut -d',' -f1 | tr -cd '[[:digit:]]' || echo 0)
        
        new_mail_count=$((master_count - slave_count))
        
        if [ "$new_mail_count" -gt 0 ]; then
          ${pkgs.libnotify}/bin/notify-send "Mail" "You have $new_mail_count new email(s)."
        fi
      '';
    };
  };

  # mbsync Hotmail Timer
  systemd.user.timers.mbsync-hotmail = {
    Unit = {
      Description = "Auto-sync Hotmail every 5 minutes";
    };
    Timer = {
      OnBootSec = "1min";
      OnUnitActiveSec = "5min";
      Persistent = false;
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };

  # USB Watch Service (Hyprland version)
  systemd.user.services.usb-watch = {
    Unit = {
      Description = "Reapply keyboard settings on USB add (Hyprland)";
    };
    Service = {
      Type = "simple";
      ExecStart = pkgs.writeShellScript "usb-watch-hyprland" ''
        ${pkgs.systemd}/bin/udevadm monitor --udev --subsystem-match=usb --property |
        while read -r line; do
            if [[ "$line" == *"add"* ]]; then
                # Re-apply Hyprland keyboard settings
                # Note: These should ideally match your hyprland.conf input block
                ${pkgs.hyprland}/bin/hyprctl keyword input:repeat_rate 50
                ${pkgs.hyprland}/bin/hyprctl keyword input:repeat_delay 300
                ${pkgs.hyprland}/bin/hyprctl keyword input:kb_layout us
                ${pkgs.hyprland}/bin/hyprctl keyword input:kb_variant intl
                ${pkgs.hyprland}/bin/hyprctl keyword input:kb_options caps:swapescape
            fi
        done
      '';
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
