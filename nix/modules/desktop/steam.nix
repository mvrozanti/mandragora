{ pkgs, ... }:

let
  gameWorkspace = pkgs.writeShellApplication {
    name = "steam-game-workspace";
    runtimeInputs = [
      pkgs.socat
      pkgs.jq
      pkgs.hyprland
      pkgs.procps
      pkgs.gnugrep
      pkgs.coreutils
      pkgs.hypr-live-instance
    ];
    text = builtins.readFile ../../../.local/bin/steam-game-workspace.sh;
  };
in
{
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    extraCompatPackages = [ pkgs.proton-ge-bin ];
    package = pkgs.steam.override { extraArgs = "-cef-disable-gpu"; };
  };

  environment.systemPackages = [ gameWorkspace ];

  systemd.user.services.steam-game-workspace = {
    description = "Move every window a Steam game opens to the gaming workspace";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${gameWorkspace}/bin/steam-game-workspace";
      Restart = "always";
      RestartSec = "3s";
    };
  };
}
