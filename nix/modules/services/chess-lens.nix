{ pkgs, ... }:

let
  launcher = pkgs.writeShellScript "chess-lens-backend" (
    builtins.readFile ../../../.local/bin/chess-lens-backend.sh
  );
in
{
  mandragora.hub.services.chess-lens-backend = {
    port = 8080;
    userService = true;
    memoryMax = "9G";
    maxRuntime = "6h";
    systemd = {
      description = "Chess Lens backend for chess.mvr.ac: JVM API behind the VPS proxy, heap capped and the engines on a 64 MB hash, so a crunch costs about 200 MB an engine instead of 400";
      after = [ "network.target" ];
      wantedBy = [ "default.target" ];
      path = [
        pkgs.jdk21
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.bash
      ];
      serviceConfig = {
        ExecStart = "${launcher}";
        EnvironmentFile = "-%h/.config/chess-lens/admin.env";
        MemorySwapMax = "0";
        CPUWeight = 20;
        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutStopSec = "20s";
      };
    };
  };
}
