{ pkgs, ... }:

let
  backup = pkgs.writeShellApplication {
    name = "music-index-backup";
    runtimeInputs = [
      pkgs.mpc
      pkgs.gawk
      pkgs.gnused
      pkgs.xz
      pkgs.age
      pkgs.git
      pkgs.coreutils
    ];
    text = builtins.readFile ../../snippets/music-index-backup.sh;
  };
in
{
  systemd.user.services.music-index-backup = {
    description = "Encrypted mirror of the music library's track index, kept as a git note beside the system config";
    after = [ "mpd.service" ];
    serviceConfig = {
      Type = "oneshot";
      Nice = 15;
      IOSchedulingClass = "idle";
      TimeoutStartSec = "5m";
      Restart = "on-failure";
      RestartSec = "1h";
      Environment = [
        "INDEX_RECIPIENT=age12qpq33wytvuhyynrwr7l25l6cde86qtuesgj47pfndf0hjny49qqeavy8v"
        "INDEX_REMOTE=https://github.com/mvrozanti/mandragora.git"
        "INDEX_REF=refs/notes/library"
        "INDEX_ANCHOR=e5b769147a067556c9a2e1f600419921901cfef2"
      ];
      ExecStart = "${backup}/bin/music-index-backup";
    };
  };

  systemd.user.paths.music-index-backup = {
    description = "Refresh the music index mirror when MPD rewrites its database";
    wantedBy = [ "default.target" ];
    pathConfig.PathChanged = "%h/.local/share/mpd/tag_cache";
  };
}
