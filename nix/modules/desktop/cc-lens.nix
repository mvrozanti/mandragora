{ pkgs, ... }:

let
  port = 7683;
in
{
  systemd.user.services.cc-lens = {
    description = "cc-lens — lens.mvr.ac · local analytics dashboard for Claude Code (~/.claude)";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.cc-lens}/bin/cc-lens-server";
      Restart = "on-failure";
      RestartSec = "10s";
      Environment = [
        "NODE_ENV=production"
        "CLAUDE_CONFIG_DIR=/home/m/.claude"
        "HOSTNAME=0.0.0.0"
        "PORT=${toString port}"
      ];
    };
    unitConfig.ConditionPathExists = "/home/m/.claude";
  };
}
