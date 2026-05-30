{ config, lib, pkgs, ... }:

let
  repo = "/home/m/Projects/slither-io-simulator";
  launcher = pkgs.writeShellScript "slither-io-serve" ''
    export PATH=${lib.makeBinPath [ pkgs.nix pkgs.git pkgs.coreutils pkgs.bash ]}:$PATH
    export HOME=/home/m
    cd ${repo}
    exec nix develop --command python serve.py
  '';
in {
  mandragora.hub.services.slither-io = {
    port = 8088;
    userService = true;
    systemd = {
      description = "slither-io-simulator HTTP server (tailnet bind, public via Caddy)";
      after = [ "network.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        WorkingDirectory = repo;
        Environment = [ "PORT=8088" "BIND=0.0.0.0" ];
        ExecStart = "${launcher}";
        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutStartSec = "300s";
      };
    };
  };
}
