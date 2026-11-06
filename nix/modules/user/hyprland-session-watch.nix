{ pkgs, lib, ... }:
let
  hyprland-session-watch = pkgs.writeShellScriptBin "hyprland-session-watch" (
    builtins.readFile ../../../.local/bin/hyprland-session-watch.sh
  );
  binPath = lib.makeBinPath [
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.libnotify
  ];
in
{
  home.packages = [ hyprland-session-watch ];

  systemd.user.services.hyprland-session-watch = {
    Unit.Description = "Warn when Hyprland runs in safe mode or an older build than the installed one";
    Service = {
      Type = "oneshot";
      Environment = [ "PATH=${binPath}" ];
      ExecStart = "${hyprland-session-watch}/bin/hyprland-session-watch";
      Nice = 15;
    };
  };

  systemd.user.timers.hyprland-session-watch = {
    Unit.Description = "Check the running Hyprland every minute";
    Timer = {
      OnActiveSec = "1min";
      OnUnitActiveSec = "1min";
      Persistent = false;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
