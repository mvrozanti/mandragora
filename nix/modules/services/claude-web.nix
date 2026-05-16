{ config, lib, pkgs, ... }:

let
  port = 7682;
  src = "/persistent/mandragora/.local/share/claude-web/app.py";
  pyEnv = pkgs.python3.withPackages (ps: [ ps.aiohttp ]);
in {
  mandragora.hub.services.claude-web = {
    port = port;
    systemd = {
      description = "claude.mvr.ac — spawn detached tmux+claude on demand, web dir picker";
      after = [ "network.target" "tailscaled.service" ];
      wants = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ (builtins.readFile ../../../.local/share/claude-web/app.py) ];
      environment = {
        CLAUDE_WEB_HOST = "0.0.0.0";
        CLAUDE_WEB_PORT = toString port;
        HOME = "/home/m";
        XDG_RUNTIME_DIR = "/run/user/1000";
      };
      path = [ pkgs.tmux pkgs.claude-code pkgs.coreutils ];
      serviceConfig = {
        Type = "simple";
        User = "m";
        Group = "users";
        WorkingDirectory = "/home/m";
        ExecStart = "${pyEnv}/bin/python ${src}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
