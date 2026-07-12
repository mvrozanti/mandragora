{ pkgs, ... }:

let
  monitor-audio-follow = pkgs.writeShellApplication {
    name = "monitor-audio-follow";
    runtimeInputs = with pkgs; [
      pulseaudio
      hyprland
      jq
      coreutils
    ];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${../../snippets/monitor-audio-follow.py} "$@"
    '';
  };
in
{
  home.packages = [ monitor-audio-follow ];

  systemd.user.services.monitor-audio-follow = {
    Unit = {
      Description = "Route each audio stream to the sink of the monitor its window lives on";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${monitor-audio-follow}/bin/monitor-audio-follow";
      Restart = "on-failure";
      RestartSec = "3";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
