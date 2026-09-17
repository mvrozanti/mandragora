{ pkgs, ... }:

let
  port = 8877;
  bridgeRun = pkgs.writeShellScriptBin "cc-pocket-bridge-run" (
    builtins.readFile ../../../.local/bin/cc-pocket-bridge.sh
  );
in
{
  mandragora.hub.services.cc-pocket-bridge = {
    inherit port;
    userService = true;
    systemd = {
      description = "CC Pocket bridge server (K9i-0/ccpocket): tailscale-only WebSocket bridge to the Claude CLI";
      after = [ "default.target" ];
      wantedBy = [ "default.target" ];
      path = [
        "${pkgs.cc-pocket-bridge}"
        "/run/current-system/sw"
        "/etc/profiles/per-user/m"
        "/run/wrappers"
        "/home/m/.nix-profile"
        "/nix/var/nix/profiles/default"
      ];
      environment = {
        BRIDGE_PORT = toString port;
        BRIDGE_HOST = "0.0.0.0";
        BRIDGE_PUBLIC_WS_URL = "ws://100.115.80.79:${toString port}";
        BRIDGE_ALLOWED_DIRS = "/home/m";
        BRIDGE_DISABLE_MDNS = "1";
      };
      serviceConfig = {
        Type = "simple";
        WorkingDirectory = "/home/m";
        ExecStart = "${bridgeRun}/bin/cc-pocket-bridge-run";
        Restart = "on-failure";
        RestartSec = "5s";
      };
      unitConfig.ConditionPathExists = "/run/current-system/sw/bin/claude";
    };
  };
}
