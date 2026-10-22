{ pkgs, lib, ... }:
let
  link-speed-watch = pkgs.writeShellScriptBin "link-speed-watch" (
    builtins.readFile ../../../.local/bin/link-speed-watch.sh
  );
  binPath = lib.makeBinPath [
    pkgs.coreutils
    pkgs.libnotify
  ];
in
{
  home.packages = [ link-speed-watch ];

  systemd.user.services.link-speed-watch = {
    Unit.Description = "Warn once per link change when a wired interface comes up below gigabit";
    Service = {
      Type = "oneshot";
      Environment = [ "PATH=${binPath}" ];
      ExecStart = "${link-speed-watch}/bin/link-speed-watch";
      Nice = 15;
    };
  };

  systemd.user.timers.link-speed-watch = {
    Unit.Description = "Check wired link speed every 5 minutes";
    Timer = {
      OnActiveSec = "1min";
      OnUnitActiveSec = "5min";
      Persistent = false;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
