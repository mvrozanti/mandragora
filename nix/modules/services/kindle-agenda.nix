{ pkgs, ... }:

let
  pyEnv = pkgs.python3.withPackages (_: [ ]);
  src = ../../hosts/mandragora-kindle/agenda/server.py;
  port = 6616;
in
{
  systemd.services.mandragora-agenda = {
    description = "mandragora-agenda — the next two weeks of the calendar behind a line protocol for mandragora-kindle";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [ (builtins.readFile ../../hosts/mandragora-kindle/agenda/server.py) ];
    path = [ pkgs.khal ];
    environment = {
      AGENDA_BIND = "0.0.0.0";
      AGENDA_PORT = toString port;
      AGENDA_TTL = "60";
      AGENDA_DAYS = "14";
      HOME = "/home/m";
    };
    serviceConfig = {
      Type = "simple";
      User = "m";
      Group = "users";
      ExecStart = "${pyEnv}/bin/python3 ${src}";
      Restart = "always";
      RestartSec = "20s";
      MemoryMax = "192M";
      Nice = 12;
    };
  };

  networking.firewall.interfaces.enp8s0.allowedTCPPorts = [ port ];
}
