{
  config,
  lib,
  pkgs,
  ...
}:

let
  usbWatch = pkgs.writeShellApplication {
    name = "usb-watch-hyprland";
    runtimeInputs = [
      pkgs.systemd
      pkgs.hyprland
      pkgs.hypr-live-instance
    ];
    text = builtins.readFile ../../../.local/bin/usb-watch-hyprland.sh;
  };
in
{
  services.mpd = {
    enable = true;
    musicDirectory = "~/Music";
    network.listenAddress = "any";
    extraConfig = builtins.readFile ../../../.config/mpd/mpd.conf;
  };

  systemd.user.services.mpd.Service = {
    WatchdogSec = "30s";
    Restart = "on-failure";
    RestartSec = 2;
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

  systemd.user.services.mpd-discord-rpc = {
    Unit = {
      After = [ "mpd.service" ];
      Wants = [ "mpd.service" ];
    };
    Service = {
      Environment = "RUST_LOG=mpd_discord_rpc=info,discord_presence=off";
      LogRateLimitIntervalSec = "1h";
      LogRateLimitBurst = 20;
    };
    Install.WantedBy = lib.mkForce [ ];
  };

  systemd.user.paths.mpd-discord-rpc = {
    Unit.Description = "Start mpd-discord-rpc once a Discord client opens its IPC socket";
    Path.PathExists = "%t/discord-ipc-0";
    Install.WantedBy = [ "default.target" ];
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
        "SASL_PATH=${pkgs.cyrus_sasl.out}/lib/sasl2:${pkgs.cyrus-sasl-xoauth2}/lib/sasl2"
      ];
      ExecStart = "${
        pkgs.writeShellApplication {
          name = "mbsync-hotmail-sync";
          runtimeInputs = with pkgs; [
            isync
            libnotify
            gnugrep
            gnused
            coreutils
            notmuch
            mutt-oauth2
            mail-menu
          ];
          text = builtins.readFile ../../../.local/bin/mbsync-hotmail-sync.sh;
        }
      }/bin/mbsync-hotmail-sync";
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
      Description = "Animate RAM RGB from the pywal palette, and RAM + AIO as a Forza Horizon speed gauge";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${config.home.profileDirectory}/bin/wal-to-rgb-daemon";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  systemd.user.services.wal-to-rgb-aio-restore = {
    Unit = {
      Description = "Restore AIO chain (D_LED1 Bottom) from pywal palette on boot";
      After = [
        "graphical-session.target"
        "wal-to-rgb-daemon.service"
      ];
      Wants = [ "wal-to-rgb-daemon.service" ];
      ConditionPathExists = "%h/.cache/matugen/colors.json";
    };
    Service = {
      Type = "oneshot";
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
      ExecStart = "${config.home.profileDirectory}/bin/wal-to-rgb";
      RemainAfterExit = true;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  systemd.user.services.ds4-lightbar = {
    Unit = {
      Description = "Paint the DualShock lightbar with the matugen accent, dimmed to its battery level";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${config.home.profileDirectory}/bin/ds4-lightbar";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  systemd.user.services.rgb-restore = {
    Unit = {
      Description = "Re-apply pywal RGB (mouse, RAM, AIO/mobo) after an openrgb restart";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = [
        "${config.home.profileDirectory}/bin/hid-wrapper"
        "${pkgs.systemd}/bin/systemctl --user restart wal-to-rgb-daemon.service"
      ];
      RemainAfterExit = false;
    };
  };

  systemd.user.services.webhook-notifier = {
    Unit = {
      Description = "Subscribe to webhook.mvr.ac SSE and emit desktop notifications";
      After = [
        "graphical-session.target"
        "network-online.target"
      ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${
        pkgs.writeShellApplication {
          name = "webhook-notifier";
          runtimeInputs = with pkgs; [
            curl
            jq
            libnotify
            xdg-utils
            coreutils
            tailscale
          ];
          text = builtins.readFile ../../../.local/bin/webhook-notifier.sh;
        }
      }/bin/webhook-notifier";
      Restart = "always";
      RestartSec = 5;
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.services.usb-watch = {
    Unit = {
      Description = "Reapply keyboard settings on USB add (Hyprland)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${usbWatch}/bin/usb-watch-hyprland";
      Restart = "on-failure";
      RestartSec = "3s";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
