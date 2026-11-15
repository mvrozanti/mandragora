{ pkgs, ... }:

let
  calendarSync = pkgs.writeShellApplication {
    name = "calendar-sync";
    runtimeInputs = with pkgs; [
      vdirsyncer
      coreutils
    ];
    text = builtins.readFile ../../../.local/bin/calendar-sync.sh;
  };

  calendarLogin = pkgs.writeShellApplication {
    name = "calendar-login";
    runtimeInputs = with pkgs; [
      vdirsyncer
      coreutils
      jq
      xdg-utils
      calendarSync
    ];
    text = builtins.readFile ../../../.local/bin/calendar-login.sh;
  };
in
{
  home.packages = [
    pkgs.vdirsyncer
    calendarSync
    calendarLogin
  ];

  home.file.".config/vdirsyncer/config".source = ../../../.config/vdirsyncer/config;

  systemd.user.services.calendar-sync = {
    Unit = {
      Description = "Sync the calendars with vdirsyncer";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${calendarSync}/bin/calendar-sync";
    };
  };

  systemd.user.timers.calendar-sync = {
    Unit = {
      Description = "Sync the calendars every 5 minutes";
    };
    Timer = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
      Persistent = false;
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}
