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
    pkgs.git
    pkgs.coreutils
    pkgs.bash
  ];
in {
  mandragora.hub.services.gource-renderer = {
    port = port;
    systemd = {
      description = "On-demand gource render service (tailnet-bound, headless NVIDIA GPU). VPS gource-api proxies here when reachable.";
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
        SDL_VIDEO_X11_FORCE_EGL = "1";
        SDL_VIDEODRIVER = "x11";
        __EGL_VENDOR_LIBRARY_FILENAMES = "/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json";
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";
        HOME = "/tmp";
        XDG_CACHE_HOME = "/tmp/cache";
        MESA_SHADER_CACHE_DIR = "/tmp/mesa-cache";
        LOG_LEVEL = "info";
      };
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pyEnv}/bin/python ${src}";
        Restart = "on-failure";
        RestartSec = "5s";
        DynamicUser = true;
        SupplementaryGroups = [ "video" "render" ];
        StateDirectory = "gource-renderer";
        ReadWritePaths = [ "/var/lib/gource-renderer" ];
        ReadOnlyPaths = [ "/etc/nixos/mandragora" ];
        DeviceAllow = [
          "/dev/dri rwm"
          "/dev/nvidia0 rwm"
          "/dev/nvidiactl rwm"
          "/dev/nvidia-modeset rwm"
          "/dev/nvidia-uvm rwm"
          "/dev/nvidia-uvm-tools rwm"
        ];
        PrivateDevices = false;
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
