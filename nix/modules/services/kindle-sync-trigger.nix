{ pkgs, ... }:

let
  src = ../../../.local/share/kindle-sync-trigger/kindle_sync_trigger.py;
in
{
  mandragora.hub.services.kindle-sync-trigger = {
    port = 6690;
    userService = true;
    systemd = {
      description = "kindle-sync-trigger — run kindle-sync on demand for kindle.mvr.ac";
      wantedBy = [ "default.target" ];
      restartTriggers = [ (builtins.readFile src) ];
      environment = {
        KINDLE_SYNC_TRIGGER_HOST = "0.0.0.0";
        KINDLE_SYNC_TRIGGER_PORT = "6690";
      };
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python3 ${src}";
        Restart = "on-failure";
        RestartSec = "5s";
        MemoryMax = "128M";
      };
    };
  };
}
