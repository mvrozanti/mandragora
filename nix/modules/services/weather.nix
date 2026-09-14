{ config, pkgs, ... }:

let
  pyEnv = pkgs.python3.withPackages (_: [ ]);
  src = ../../hosts/mandragora-kindle/weather/server.py;
  port = 6615;
in
{
  systemd.services.mandragora-weather = {
    description = "mandragora-weather — cached forecast behind a line protocol for mandragora-kindle";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [ (builtins.readFile ../../hosts/mandragora-kindle/weather/server.py) ];
    environment = {
      WEATHER_BIND = "0.0.0.0";
      WEATHER_PORT = toString port;
      WEATHER_TTL = "900";
      WEATHER_KEY_FILE = config.sops.secrets."weather/api_key".path;
      WEATHER_CITY_ID = "3448439";
      WEATHER_UNITS = "metric";
    };
    serviceConfig = {
      Type = "simple";
      User = "m";
      Group = "users";
      ExecStart = "${pyEnv}/bin/python3 ${src}";
      Restart = "always";
      RestartSec = "20s";
      MemoryMax = "128M";
      Nice = 12;
    };
  };

  networking.firewall.interfaces.enp8s0.allowedTCPPorts = [ port ];
}
