{ pkgs, ... }:

let
  port = 6691;
  slot = "/home/m/.local/state/plugin-slot";
in
{
  mandragora.hub.services.plugin-slot = {
    inherit port;
    userService = true;
    memoryMax = "2G";
    systemd = {
      description = "plugin slot — runs the private flake linked at ~/.local/state/plugin-slot for the phone app's plugin screen over the tailnet";
      wantedBy = [ "default.target" ];
      path = [
        pkgs.claude-code
        pkgs.git
        pkgs.nix
        "/etc/profiles/per-user/m"
        "/nix/var/nix/profiles/default"
        "/run/current-system/sw"
      ];
      environment = {
        PLUGIN_PORT = toString port;
        PLUGIN_INBOX_URL = "http://127.0.0.1:6688/api/inbox";
      };
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.nix}/bin/nix run --no-write-lock-file ${slot}";
        Restart = "on-failure";
        RestartSec = "30s";
        TimeoutStartSec = "10min";
      };
      unitConfig.ConditionPathExists = "${slot}/flake.nix";
    };
  };
}
