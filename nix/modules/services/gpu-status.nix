{ config, lib, pkgs, ... }:

let
  port = 6684;
  src = "/persistent/mandragora/.local/share/gpu-status/server.py";
  pyEnv = pkgs.python3.withPackages (_: []);
in {
  mandragora.hub.services.gpu-status = {
    inherit port;
    systemd = {
      description = "hub.mvr.ac /api/gpu — gpu-lock + nvidia-smi snapshot";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        GPU_STATUS_HOST = "0.0.0.0";
        GPU_STATUS_PORT = toString port;
      };
      path = [ config.hardware.nvidia.package ];
      restartTriggers = [ (builtins.readFile ../../../.local/share/gpu-status/server.py) ];
      serviceConfig = {
        ExecStart = "${pyEnv}/bin/python ${src}";
        Restart = "on-failure";
        RestartSec = "5s";
        DynamicUser = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
      };
      unitConfig = {
        ConditionPathExists = [ "/dev/nvidia0" src ];
      };
    };
  };
}
