{ config, lib, pkgs, ... }:

let
  src = "/persistent/mandragora/.local/share/rgb-control/rgb-control.py";
  pyEnv = pkgs.python3.withPackages (ps: [ ps.aiohttp ]);
  recoverScript = pkgs.writeShellScript "rgb-control-recover-keyleds" ''
    set +e
    export XDG_RUNTIME_DIR=/run/user/1000
    ${pkgs.systemd}/bin/systemctl --user restart keyledsd.service
    ${pkgs.systemd}/bin/systemctl --user restart keyleds-workspace-watcher.service
    exit 0
  '';
  stopOpenrgbScript = pkgs.writeShellScript "rgb-control-stop-openrgb" ''
    set +e
    ${pkgs.sudo}/bin/sudo -n /run/current-system/sw/bin/systemctl stop openrgb
    exit 0
  '';
in {
  mandragora.hub.services.rgb-control = {
    port = 6681;
    systemd = {
      description = "rgb-control web — per-device openrgb UI";
      after = [ "network.target" "tailscaled.service" ];
      wants = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        RGB_HOST = "0.0.0.0";
        RGB_PORT = "6681";
        HOME = "/home/m";
        XDG_RUNTIME_DIR = "/run/user/1000";
        DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/1000/bus";
      };
      path = [ pkgs.openrgb-with-all-plugins pkgs.systemd ];
      serviceConfig = {
        User = "m";
        Group = "users";
        ExecStartPre = "${stopOpenrgbScript}";
        ExecStart = "${pyEnv}/bin/python ${src}";
        ExecStopPost = "${recoverScript}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
