{ pkgs, ... }:

let
  port = 7682;
  src = "/persistent/mandragora/.local/share/claude-web/app.py";
  pyEnv = pkgs.python3.withPackages (ps: [ ps.aiohttp ]);
in {
  mandragora.hub.services.claude-web = {
    inherit port;
    userService = true;
    systemd = {
      description = "claude.mvr.ac — add a tmux window running claude to the current session, web dir picker";
      after = [ "default.target" ];
      wantedBy = [ "default.target" ];
      restartTriggers = [ (builtins.readFile ../../../.local/share/claude-web/app.py) ];
      environment = {
        CLAUDE_WEB_HOST = "0.0.0.0";
        CLAUDE_WEB_PORT = toString port;
        TMUX_TMPDIR = "/run/user/1000";
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
        WorkingDirectory = "/home/m";
        ExecStart = "${pyEnv}/bin/python ${src}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
