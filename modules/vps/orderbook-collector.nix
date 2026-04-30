{ config, lib, pkgs, ... }:

let
  workDir = "/var/lib/orderbook-collector";
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    aiohttp
    websockets
    requests
    pyarrow
    pandas
    numpy
  ]);
in
{
  users.users.orderbook = {
    isSystemUser = true;
    group = "orderbook";
    home = workDir;
    createHome = false;
  };
  users.groups.orderbook = { };

  systemd.tmpfiles.rules = [
    "d ${workDir}      0755 orderbook orderbook - -"
    "d ${workDir}/data 0755 orderbook orderbook - -"
  ];

  systemd.services.orderbook-collector = {
    description = "Orderbook Multi-Stream Collector (Spot + Futures + Funding)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "orderbook";
      Group = "orderbook";
      WorkingDirectory = workDir;
      ExecStart = "${pkgs.bash}/bin/bash -c 'exec ${pythonEnv}/bin/python3 -u collector.py'";
      StandardOutput = "append:${workDir}/collector.log";
      StandardError = "append:${workDir}/collector.log";
      Restart = "on-failure";
      RestartSec = "10s";
      KillSignal = "SIGTERM";
      TimeoutStopSec = "30s";
    };
  };
}
