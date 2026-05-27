{ config, lib, pkgs, ... }:

let
  port = 9991;
  host = "100.115.80.79";
  src = "/persistent/mandragora/.local/share/gource-renderer/server.py";
  pyEnv = pkgs.python3.withPackages (ps: [ ps.fastapi ps.uvicorn ps.httpx ps.pydantic ]);
  runtimePath = lib.makeBinPath [
    pkgs.gource
    pkgs.ffmpeg-full
    pkgs.xorg.xorgserver
    pkgs.xorg.xauth
    pkgs.mesa
    pkgs.git
    pkgs.coreutils
    pkgs.bash
  ];
in {
  mandragora.hub.services.gource-renderer = {
    port = port;
    systemd = {
      description = "On-demand gource render service (tailnet-bound). VPS gource-api proxies here when reachable.";
      after = [ "network-online.target" "tailscaled.service" ];
      wants = [ "network-online.target" "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ (builtins.readFile ../../../.local/share/gource-renderer/server.py) ];
      environment = {
        GOURCE_LISTEN_HOST = host;
        GOURCE_LISTEN_PORT = toString port;
        GOURCE_REPO_PATH = "/etc/nixos/mandragora";
        GOURCE_CACHE_DIR = "/var/lib/gource-renderer/cache";
        PATH = lib.mkForce runtimePath;
        LD_LIBRARY_PATH = "${pkgs.mesa}/lib:${pkgs.libGL}/lib";
        LIBGL_DRIVERS_PATH = "${pkgs.mesa}/lib/dri";
        LIBGL_ALWAYS_SOFTWARE = "1";
        GALLIUM_DRIVER = "llvmpipe";
        LOG_LEVEL = "info";
      };
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pyEnv}/bin/python ${src}";
        Restart = "on-failure";
        RestartSec = "5s";
        DynamicUser = true;
        StateDirectory = "gource-renderer";
        ReadWritePaths = [ "/var/lib/gource-renderer" ];
        ReadOnlyPaths = [ "/etc/nixos/mandragora" ];
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        MemoryMax = "2G";
        CPUQuota = "400%";
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /persistent/var/lib/private/gource-renderer 0700 - - - -"
  ];

  environment.persistence."/persistent".directories = [
    "/var/lib/private/gource-renderer"
  ];
}
