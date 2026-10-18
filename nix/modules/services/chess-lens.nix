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
    memoryMax = "3G";
    maxRuntime = "6h";
    systemd = {
      description = "Chess Lens backend for chess.mvr.ac: JVM API behind the VPS proxy, heap capped so an idle server shrinks instead of growing to a quarter of RAM";
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
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
