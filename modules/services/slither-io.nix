{ config, lib, pkgs, ... }:

let
  repo = "/home/m/Projects/slither-io-simulator";
in {
  mandragora.hub.services.slither-io = {
    port = 8080;
    systemd = {
      description = "slither-io-simulator HTTP server (tailnet bind, public via Caddy)";
      after = [ "network.target" "tailscaled.service" ];
      wants = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = "m";
        Group = "users";
        WorkingDirectory = repo;
        Environment = [ "PORT=8080" "BIND=0.0.0.0" ];
        ExecStart = "${pkgs.python3}/bin/python3 ${repo}/serve.py";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
