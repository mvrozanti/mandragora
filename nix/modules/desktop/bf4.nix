{ pkgs, ... }:

let
  pyEnv = pkgs.python3.withPackages (ps: [ ps.evdev ]);
  bf4ModeWatcher = pkgs.writeShellApplication {
    name = "bf4-mode-watcher";
    runtimeInputs = [
      pkgs.socat
      pkgs.jq
      pkgs.hyprland
    ];
    text = builtins.readFile ../../../.local/bin/bf4-mode-watcher.sh;
  };
  bf4AimWatcher = pkgs.writeShellApplication {
    name = "bf4-aim-watcher";
    runtimeInputs = [ pkgs.hyprland ];
    text = ''
      exec ${pyEnv}/bin/python3 ${../../../.local/bin/bf4-aim-watcher.py} "$@"
    '';
  };
in
{
  environment.systemPackages = [
    bf4ModeWatcher
    bf4AimWatcher
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

  systemd.user.services.bf4-aim-watcher = {
    description = "Halve mouse sensitivity while Alt is held in BF4";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${bf4AimWatcher}/bin/bf4-aim-watcher";
      Restart = "on-failure";
      RestartSec = "3s";
    };
  };
}
