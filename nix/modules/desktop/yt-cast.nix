{ lib, pkgs, ... }:

let
  port = 8099;
  lan = "enp8s0";
  deviceName = "mandragora-desktop";
  mpvArgs = [
    "--autofit=1280x720"
    "--geometry=50%:50%"
  ];
  escapeSystemdSpecifiers = lib.replaceStrings [ "%" ] [ "%%" ];
in
{
  systemd.user.services.yt-cast = {
    description = "yt-cast-mpv — YouTube Cast receiver advertising mandragora-desktop over DIAL";
    wantedBy = [ "hyprland-session.target" ];
    partOf = [ "hyprland-session.target" ];
    after = [ "hyprland-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.yt-cast-mpv}/bin/yt-cast-mpv";
      Restart = "on-failure";
      RestartSec = "10s";
      Environment = [
        "YT_CAST_DEVICE_NAME=${deviceName}"
        "YT_CAST_PORT=${toString port}"
        "YT_CAST_INTERFACES=${lan}"
        "YT_CAST_MPV_ARGS=\"${escapeSystemdSpecifiers (lib.concatStringsSep " " mpvArgs)}\""
      ];
    };
  };

  networking.firewall.interfaces.${lan} = {
    allowedTCPPorts = [ port ];
    allowedUDPPorts = [ 1900 ];
  };
}
