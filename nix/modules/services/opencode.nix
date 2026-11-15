{ pkgs, ... }:

let
  port = 4096;
  serveScript = ../../../.local/bin/opencode-serve.sh;
  configFile = ../../../.config/opencode/opencode.json;
  serve = pkgs.writeShellScriptBin "opencode-serve" (builtins.readFile serveScript);
in
{
  mandragora.hub.services.opencode-serve = {
    inherit port;
    userService = true;
    memoryMax = "10G";
    systemd = {
      description = "opencode-serve — one opencode server on the tailnet; the desktop tui (oc) and the phone attach to the same sessions";
      wantedBy = [ "default.target" ];
      restartTriggers = [
        (builtins.readFile serveScript)
        (builtins.readFile configFile)
      ];
      path = [
        pkgs.opencode
        pkgs.coreutils
        "/run/wrappers"
        "/home/m/.nix-profile"
        "/etc/profiles/per-user/m"
        "/nix/var/nix/profiles/default"
        "/run/current-system/sw"
      ];
      environment = {
        OPENCODE_HOST = "0.0.0.0";
        OPENCODE_PORT = toString port;
      };
      serviceConfig = {
        Type = "simple";
        WorkingDirectory = "/home/m";
        ExecStart = "${serve}/bin/opencode-serve";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
