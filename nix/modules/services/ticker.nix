{ pkgs, ... }:

let
  pyEnv = pkgs.python3.withPackages (_: [ ]);
  src = ../../hosts/mandragora-kindle/ticker/server.py;
  port = 6614;
in
{
  systemd.services.mandragora-ticker = {
    description = "mandragora-ticker — cached market quotes behind a line protocol for mandragora-kindle";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [ (builtins.readFile ../../hosts/mandragora-kindle/ticker/server.py) ];
    environment = {
      TICKER_BIND = "0.0.0.0";
      TICKER_PORT = toString port;
      TICKER_TTL = "300";
      TICKER_HTTP_TIMEOUT = "20";
    };
    serviceConfig = {
      Type = "simple";
      User = "m";
      Group = "users";
      ExecStart = "${pyEnv}/bin/python3 ${src}";
      Restart = "always";
      RestartSec = "15s";
      MemoryMax = "256M";
      Nice = 10;
    };
  };

  networking.firewall.interfaces.enp8s0.allowedTCPPorts = [ port ];
}
