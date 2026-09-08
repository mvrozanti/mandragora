{ pkgs, ... }:

let
  port = 7682;
  src = ../../../.local/share/claude-web;
  pyEnv = pkgs.python3.withPackages (ps: [ ps.aiohttp ]);
in
{
  mandragora.hub.services.claude-web = {
    inherit port;
    userService = true;
    systemd = {
      description = "claude.mvr.ac — add a tmux window running claude to the current session, web dir picker";
      after = [ "default.target" ];
      wantedBy = [ "default.target" ];
      restartTriggers = [
        (builtins.readFile ../../../.local/share/claude-web/app.py)
        (builtins.readFile ../../../.local/share/claude-web/static/index.html)
        (builtins.readFile ../../../.local/share/claude-web/static/claude.css)
        (builtins.readFile ../../../.local/share/claude-web/static/claude.js)
        (builtins.readFile ../../../.local/share/claude-web/static/theme.css)
        (builtins.readFile ../../../.local/share/claude-web/static/components.css)
        (builtins.readFile ../../../.local/share/claude-web/static/theme.js)
      ];
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
        ExecStart = "${pyEnv}/bin/python ${src}/app.py";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
