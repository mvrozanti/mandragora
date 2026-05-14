{ config, lib, pkgs, ... }:

let
  src = "/persistent/mandragora/.local/share/rgb-control/rgb-control.py";
  pyEnv = pkgs.python3.withPackages (ps: [ ps.aiohttp ]);
in {
  mandragora.hub.services.rgb-control = {
    port = 6681;
    systemd = {
      description = "rgb-control web — openrgb preset web UI";
      after = [ "network.target" "tailscaled.service" ];
      wants = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        RGB_HOST = "0.0.0.0";
        RGB_PORT = "6681";
      };
      path = [ pkgs.openrgb-with-all-plugins pkgs.sudo pkgs.systemd ];
      serviceConfig = {
        User = "m";
        Group = "users";
        ExecStart = "${pyEnv}/bin/python ${src}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
