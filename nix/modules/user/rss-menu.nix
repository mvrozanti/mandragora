{ config, pkgs, lib, ... }:

let
  pyEnv = pkgs.python3.withPackages (ps: with ps; [ feedparser ]);

  rss-menu = pkgs.writeShellApplication {
    name = "rss-menu";
    runtimeInputs = with pkgs; [ rofi libnotify xdg-utils procps systemd ];
    text = ''
      exec ${pyEnv}/bin/python3 ${../../snippets/rss-menu.py} "$@"
    '';
  };
in
{
  home.packages = [ rss-menu ];

  systemd.user.services.rss-menu-poll = {
    Unit = {
      Description = "Fetch & LLM-classify RSS feeds for waybar rss-menu";
      After = [ "graphical-session.target" "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${rss-menu}/bin/rss-menu poll";
      Nice = 10;
    };
  };

  systemd.user.timers.rss-menu-poll = {
    Unit = {
      Description = "Periodic RSS poll for waybar rss-menu";
    };
    Timer = {
      OnBootSec = "2min";
      OnUnitActiveSec = "15min";
      RandomizedDelaySec = "60s";
      Persistent = false;
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}
