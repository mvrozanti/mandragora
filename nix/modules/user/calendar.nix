{ pkgs, ... }:

let
  calendarSync = pkgs.writeShellApplication {
    name = "calendar-sync";
    runtimeInputs = with pkgs; [
      vdirsyncer
      coreutils
      findutils
      gnugrep
      curl
    ];
    text = builtins.readFile ../../../.local/bin/calendar-sync.sh;
  };

  calendarOauth = pkgs.writers.writePython3Bin "calendar-oauth" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ../../../.local/bin/calendar-oauth.py);

  davmailSettings = ../../../.config/davmail/davmail.properties;

  calendarLogin = pkgs.writeShellApplication {
    name = "calendar-login";
    runtimeInputs = with pkgs; [
      vdirsyncer
      coreutils
      jq
      xdg-utils
      systemd
      calendarSync
      calendarOauth
    ];
    text = builtins.readFile ../../../.local/bin/calendar-login.sh;
  };
in
{
  home.packages = [
    pkgs.vdirsyncer
    calendarSync
    calendarLogin
    calendarOauth
  ];

  home.file.".config/vdirsyncer/config".source = ../../../.config/vdirsyncer/config;

  systemd.user.services.calendar-sync = {
    Unit = {
      Description = "Sync the calendars with vdirsyncer";
      After = [
        "network-online.target"
        "davmail.service"
      ];
      Wants = [
        "network-online.target"
        "davmail.service"
      ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${calendarSync}/bin/calendar-sync";
    };
  };

  systemd.user.services.davmail = {
    Unit = {
      Description = "DavMail: the Hotmail calendar as CalDAV on localhost";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
      ConditionFileNotEmpty = "%S/davmail/tokens.properties";
    };
    Service = {
      ExecStartPre = "${pkgs.coreutils}/bin/install -D -m 600 ${davmailSettings} %S/davmail/davmail.properties";
      ExecStart = "${pkgs.davmail}/bin/davmail -server %S/davmail/davmail.properties";
      Environment = [ "\"JAVA_OPTS=-Xmx192M -Djava.awt.headless=true\"" ];
      UnsetEnvironment = [
        "DISPLAY"
        "WAYLAND_DISPLAY"
      ];
      Restart = "on-failure";
      RestartSec = "15s";
      MemoryMax = "384M";
    };
    Install = {
      WantedBy = [ "default.target" ];
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
