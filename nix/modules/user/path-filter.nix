{ lib, pkgs, ... }:

let
  scrubber = pkgs.writeShellScriptBin "recent-files-scrub"
    (builtins.readFile ../../snippets/recent-files-scrub.sh);
in
{
  home.packages = [ scrubber ];

  systemd.user.services.recent-files-filter = {
    Unit = {
      Description = "Drop excluded paths from recently-used.xbel";
    };
    Service = {
      Type = "oneshot";
      Environment = "PATH=${lib.makeBinPath [ pkgs.python3 pkgs.coreutils pkgs.bash ]}";
      ExecStart = "${scrubber}/bin/recent-files-scrub";
    };
  };

  systemd.user.paths.recent-files-filter = {
    Unit = {
      Description = "Watch recently-used.xbel for changes";
    };
    Path = {
      PathModified = "%h/.local/share/recently-used.xbel";
      Unit = "recent-files-filter.service";
    };
    Install.WantedBy = [ "default.target" ];
  };

  home.activation.seedPathExclusions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -e "$HOME/.config/path-exclusions" ]; then
      install -Dm600 /dev/null "$HOME/.config/path-exclusions"
    fi
  '';
}
