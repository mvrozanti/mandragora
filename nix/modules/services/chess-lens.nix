{ pkgs, ... }:

let
  launcher = pkgs.writeShellScript "chess-lens-backend" (
    builtins.readFile ../../../.local/bin/chess-lens-backend.sh
  );
  gameHold = pkgs.writeShellScript "chess-lens-game-hold" (
    builtins.readFile ../../../.local/bin/chess-lens-game-hold.sh
  );
  holdFile = "%t/chess-lens/hold";
in
{
  systemd.user.services.chess-lens-game-hold = {
    description = "Hold the chess-lens crunch and cap the backend at one core while a Steam game runs";
    wantedBy = [ "default.target" ];
    path = [
      pkgs.procps
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.systemd
    ];
    environment = {
      CHESS_LENS_HOLD_FILE = holdFile;
      CHESS_LENS_UNIT = "chess-lens-backend.service";
      GAME_HOLD_CPU_QUOTA = "100%";
    };
    restartTriggers = [ (builtins.hashFile "sha256" ../../../.local/bin/chess-lens-game-hold.sh) ];
    serviceConfig = {
      ExecStart = "${gameHold}";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  mandragora.hub.services.chess-lens-backend = {
    port = 8080;
    userService = true;
    memoryMax = "9G";
    maxRuntime = "6h";
    systemd = {
      description = "Chess Lens backend for chess.mvr.ac: JVM API behind the VPS proxy, heap capped so an idle server shrinks instead of growing to a quarter of RAM";
      after = [ "network.target" ];
      wantedBy = [ "default.target" ];
      environment.CRUNCH_HOLD_FILE = holdFile;
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
