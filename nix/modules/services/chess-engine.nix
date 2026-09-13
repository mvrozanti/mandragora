{ pkgs, ... }:

let
  pyEnv = pkgs.python3.withPackages (_: [ ]);
  src = ../../hosts/mandragora-kindle/chess/server.py;
  port = 6613;
in
{
  systemd.services.mandragora-chess-engine = {
    description = "mandragora-chess-engine — stockfish behind a line protocol for mandragora-kindle";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [ (builtins.readFile ../../hosts/mandragora-kindle/chess/server.py) ];
    environment = {
      CHESS_ENGINE_BIN = "${pkgs.stockfish}/bin/stockfish";
      CHESS_ENGINE_BIND = "0.0.0.0";
      CHESS_ENGINE_PORT = toString port;
      CHESS_ENGINE_DEFAULT_MOVETIME = "1000";
      CHESS_ENGINE_MAX_MOVETIME = "5000";
      CHESS_ENGINE_THREADS = "2";
      CHESS_ENGINE_HASH = "64";
    };
    serviceConfig = {
      Type = "simple";
      User = "m";
      Group = "users";
      ExecStart = "${pyEnv}/bin/python3 ${src}";
      Restart = "always";
      RestartSec = "5s";
      MemoryMax = "512M";
      Nice = 5;
    };
  };

  networking.firewall.interfaces.enp8s0.allowedTCPPorts = [ port ];
}
