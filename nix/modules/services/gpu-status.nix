{ config, lib, pkgs, ... }:

let
  src = ../../../.local/share/gpu-status/gpu_status.py;
in {
  mandragora.hub.services.gpu-status = {
    port = 6684;
    systemd = {
      description = "gpu-status — JSON snapshot of gpu_lock holder + nvidia-smi for hub.mvr.ac";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        GPU_STATUS_HOST = "0.0.0.0";
        GPU_STATUS_PORT = "6684";
        GPU_LOCK_DIR = "/dev/shm/gpu-lock";
        NVIDIA_SMI = "/run/current-system/sw/bin/nvidia-smi";
      };
      serviceConfig = {
        Type = "simple";
        DynamicUser = false;
        User = "m";
        Group = "users";
        ExecStart = "${pkgs.python3}/bin/python3 ${src}";
        Restart = "on-failure";
        RestartSec = "5s";
        MemoryMax = "128M";
      };
    };
  };
}
