{ pkgs, ... }:

let
  tailnet = builtins.fromJSON (builtins.readFile ../../snippets/tailnet.json);

  kindleSync = pkgs.writeShellApplication {
    name = "kindle-sync";
    runtimeInputs =
      (with pkgs; [
        openssh
        coreutils
        findutils
        gnutar
        diffutils
        gawk
      ])
      ++ [ kindleArt ];
    text = builtins.readFile ../../../.local/bin/kindle-sync.sh;
  };

  kindleArt = pkgs.writeShellApplication {
    name = "kindle-art";
    runtimeInputs = with pkgs; [
      bash
      openssh
      coreutils
      findutils
      gnutar
      imagemagick
    ];
    excludeShellChecks = [
      "SC2012"
      "SC2016"
    ];
    text = builtins.readFile ../../../.local/bin/kindle-art.sh;
  };

  kindleSyncWatch = pkgs.writeShellApplication {
    name = "kindle-sync-watch";
    runtimeInputs = [
      pkgs.inotify-tools
      kindleSync
    ];
    text = builtins.readFile ../../../.local/bin/kindle-sync-watch.sh;
  };
in
{
  environment.systemPackages = [
    kindleArt
    kindleSync
    kindleSyncWatch
  ];

  systemd.user.services.kindle-sync-watch = {
    description = "Watch the library and wallpapers, push changes to the kindle";
    wantedBy = [ "default.target" ];
    after = [ "network-online.target" ];
    environment.KINDLE_HOST = tailnet.kindle.ip;
    serviceConfig = {
      ExecStart = "${kindleSyncWatch}/bin/kindle-sync-watch";
      Restart = "always";
      RestartSec = 30;
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };

  systemd.user.services.kindle-sync = {
    description = "Reconcile the kindle library and wallpapers";
    environment.KINDLE_HOST = tailnet.kindle.ip;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${kindleSync}/bin/kindle-sync all";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };

  systemd.user.timers.kindle-sync = {
    description = "Periodic kindle reconcile for changes missed while it was offline";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitActiveSec = "30m";
      RandomizedDelaySec = "2m";
      Persistent = true;
    };
  };
}
