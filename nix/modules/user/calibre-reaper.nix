{ pkgs, lib, ... }:
let
  calibre-reaper = pkgs.writeShellScriptBin "calibre-reaper" (
    builtins.readFile ../../../.local/bin/calibre-reaper.sh
  );
  binPath = lib.makeBinPath [
    pkgs.procps
    pkgs.gnugrep
    pkgs.gawk
    pkgs.coreutils
    pkgs.util-linux
  ];
in
{
  home.packages = [ calibre-reaper ];

  systemd.user.services.calibre-reaper = {
    Unit.Description = "Reap orphaned calibre parallel pipe-workers so they do not accumulate into zombie thread-groups";
    Service = {
      Type = "oneshot";
      Environment = [ "PATH=${binPath}" ];
      ExecStart = "${calibre-reaper}/bin/calibre-reaper";
      Nice = 15;
    };
  };

  systemd.user.timers.calibre-reaper = {
    Unit.Description = "Poll for orphaned calibre pipe-workers";
    Timer = {
      OnActiveSec = "30s";
      OnUnitActiveSec = "1h";
      Persistent = false;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
