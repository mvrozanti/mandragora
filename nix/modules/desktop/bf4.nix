{ pkgs, ... }:

let
  bf4Aim = pkgs.writeShellApplication {
    name = "bf4-aim";
    runtimeInputs = [ pkgs.hyprland ];
    text = builtins.readFile ../../../.local/bin/bf4-aim.sh;
  };
  bf4ModeWatcher = pkgs.writeShellApplication {
    name = "bf4-mode-watcher";
    runtimeInputs = [
      pkgs.socat
      pkgs.jq
      pkgs.hyprland
    ];
    text = builtins.readFile ../../../.local/bin/bf4-mode-watcher.sh;
  };
in
{
  environment.systemPackages = [
    bf4Aim
    bf4ModeWatcher
  ];

  systemd.user.services.bf4-mode-watcher = {
    description = "Toggle Hyprland BF4 submap and aim sensitivity on focus";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${bf4ModeWatcher}/bin/bf4-mode-watcher";
      Restart = "on-failure";
      RestartSec = "3s";
    };
  };
}
