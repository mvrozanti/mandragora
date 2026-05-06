{ config, pkgs, ... }:

{
  services.mpd = {
    enable = true;
    musicDirectory = "~/Music";
    network.listenAddress = "any";
    extraConfig = builtins.readFile ../../.config/mpd/mpd.conf;
  };

  services.mpd-discord-rpc = {
    enable = true;
    settings = {
      hosts = [ "localhost:6600" ];
      format = {
        details = "$title";
        state = "$artist / $album";
        timestamp = "both";
        large_image = "notes";
        small_image = "notes";
      };
    };
  };

  systemd.user.services.mpd-discord-rpc.Unit = {
    After = [ "mpd.service" ];
    Wants = [ "mpd.service" ];
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
      Environment = [
        "GPG_TTY=/dev/tty"
        "SASL_PATH=${pkgs.cyrus_sasl}/lib/sasl2:${pkgs.cyrus-sasl-xoauth2}/lib/sasl2"
      ];
      ExecStart = "${pkgs.writeShellApplication {
        name = "mbsync-hotmail-sync";
        runtimeInputs = with pkgs; [ isync libnotify gnugrep coreutils notmuch ];
        text = builtins.readFile ../../.local/bin/mbsync-hotmail-sync.sh;
      }}/bin/mbsync-hotmail-sync";
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

  systemd.user.services.wal-to-rgb-daemon = {
    Unit = {
      Description = "Animate RAM RGB colors from pywal palette";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${config.home.profileDirectory}/bin/wal-to-rgb-daemon";
      Restart = "on-failure";
      RestartSec = 5;
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
