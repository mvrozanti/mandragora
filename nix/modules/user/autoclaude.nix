{ pkgs, ... }:

{
  home.packages = [ pkgs.autoclaude ];

  systemd.user.services.autoclaude = {
    Unit = {
      Description = "Auto-dismiss Claude Code rate-limit picker + resume on reset";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.autoclaude}/bin/autoclaude -headless";
      Environment = [ "TMUX_TMPDIR=/run/user/1000" ];
      Restart = "on-failure";
      RestartSec = 5;
      StandardOutput = "journal";
      StandardError = "journal";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
