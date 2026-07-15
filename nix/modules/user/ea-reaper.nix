{ pkgs, lib, ... }:
let
  ea-reaper = pkgs.writeShellScriptBin "ea-reaper" (
    builtins.readFile ../../../.local/bin/ea-reaper.sh
  );
  binPath = lib.makeBinPath [
    pkgs.procps
    pkgs.gnugrep
    pkgs.coreutils
    pkgs.util-linux
  ];
in
{
  home.packages = [ ea-reaper ];

  systemd.user.services.ea-reaper = {
    Unit.Description = "Reap orphaned EA/wine sessions so Lutris does not wedge on Stop";
    Service = {
      Type = "oneshot";
      Environment = [ "PATH=${binPath}" ];
      ExecStart = "${ea-reaper}/bin/ea-reaper";
      Nice = 15;
    };
  };

  systemd.user.timers.ea-reaper = {
    Unit.Description = "Poll for orphaned EA/wine sessions in the Origin/EA App prefixes";
    Timer = {
      OnActiveSec = "30s";
      OnUnitActiveSec = "20s";
      Persistent = false;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
