{ lib, pkgs, ... }:

let
  tailnet = builtins.fromJSON (builtins.readFile ../../snippets/tailnet.json);
  port = 9991;
  host = tailnet.desktop.ip;
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
    inherit port;
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
        HOME = "/tmp";
        XDG_CACHE_HOME = "/tmp/cache";
        MESA_SHADER_CACHE_DIR = "/tmp/mesa-cache";
        GIT_CONFIG_COUNT = "1";
        GIT_CONFIG_KEY_0 = "safe.directory";
        GIT_CONFIG_VALUE_0 = "*";
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
        MemoryMax = "4G";
        CPUQuota = "1200%";
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
