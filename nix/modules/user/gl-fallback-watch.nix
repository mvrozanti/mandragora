{ pkgs, lib, ... }:
let
  gl-fallback-watch = pkgs.writeShellScriptBin "gl-fallback-watch" (
    builtins.readFile ../../../.local/bin/gl-fallback-watch.sh
  );
  binPath = lib.makeBinPath [
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.libnotify
  ];
in
{
  home.packages = [ gl-fallback-watch ];

  systemd.user.services.gl-fallback-watch = {
    Unit.Description = "Warn once per process when a GUI program fell back to llvmpipe software rendering";
    Service = {
      Type = "oneshot";
      Environment = [ "PATH=${binPath}" ];
      ExecStart = "${gl-fallback-watch}/bin/gl-fallback-watch";
      Nice = 15;
    };
  };

  systemd.user.timers.gl-fallback-watch = {
    Unit.Description = "Look every 10 minutes for processes rendering on llvmpipe";
    Timer = {
      OnActiveSec = "2min";
      OnUnitActiveSec = "10min";
      Persistent = false;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
