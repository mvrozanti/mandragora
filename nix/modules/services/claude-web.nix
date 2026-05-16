{ config, lib, pkgs, ... }:

let
  port = 7682;
  launchSrc = "/persistent/mandragora/.local/share/claude-web/launch.sh";

  runtimeEnv = pkgs.buildEnv {
    name = "claude-web-runtime-env";
    paths = with pkgs; [
      bashInteractive
      coreutils
      findutils
      fzf
      git
      gnused
      ncurses
      tmux
      claude-code
    ];
  };

  launchWrapper = pkgs.writeShellScript "claude-web-launch-wrapper" ''
    export PATH=${runtimeEnv}/bin:$PATH
    export HOME=/home/m
    export TERM=''${TERM:-xterm-256color}
    export LANG=''${LANG:-en_US.UTF-8}
    exec ${pkgs.bashInteractive}/bin/bash ${launchSrc} "$@"
  '';
in {
  mandragora.hub.services.claude-web = {
    port = port;
    systemd = {
      description = "claude.mvr.ac — ttyd + dir-picker + tmux + claude";
      after = [ "network.target" "tailscaled.service" ];
      wants = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ (builtins.readFile ../../../.local/share/claude-web/launch.sh) ];
      serviceConfig = {
        User = "m";
        Group = "users";
        WorkingDirectory = "/home/m";
        ExecStart = "${pkgs.ttyd}/bin/ttyd -p ${toString port} -W -a -t titleFixed=claude.mvr.ac -t fontSize=14 ${launchWrapper}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
