{ pkgs, ... }:

let
  port = 7691;
  backendDir = "/home/m/Projects/Edgard/web/backend";
  pyEnv = pkgs.python3.withPackages (ps: [ ps.aiohttp ]);
in {
  mandragora.hub.services.edgard-web = {
    inherit port;
    userService = true;
    systemd = {
      description = "cv-es.mvr.ac — Edgard's CV workshop (Typst editor + sandboxed assistant)";
      after = [ "default.target" ];
      wantedBy = [ "default.target" ];
      environment = {
        EDGARD_WEB_HOST = "0.0.0.0";
        EDGARD_WEB_PORT = toString port;
        PYTHONUNBUFFERED = "1";
      };
      path = [
        "/run/wrappers"
        "/home/m/.nix-profile"
        "/etc/profiles/per-user/m"
        "/nix/var/nix/profiles/default"
        "/run/current-system/sw"
      ];
      serviceConfig = {
        Type = "simple";
        WorkingDirectory = backendDir;
        ExecStart = "${pyEnv}/bin/python ${backendDir}/app.py";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
