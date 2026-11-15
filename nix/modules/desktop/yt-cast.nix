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
  ssdpGroup = "239.255.255.250";
  igmpKeepalive = pkgs.writers.writePython3Bin "igmp-keepalive" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ../../snippets/igmp-keepalive.py);
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

  systemd.services.yt-cast-igmp-keepalive = {
    description = "Re-announce SSDP multicast membership on ${lan} so the router's IGMP snooping keeps forwarding phone discovery to yt-cast";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      ExecStart = "${igmpKeepalive}/bin/igmp-keepalive --interface ${lan} --interval 60 ${ssdpGroup}";
      Restart = "always";
      RestartSec = "10s";
      DynamicUser = true;
      AmbientCapabilities = [ "CAP_NET_RAW" ];
      CapabilityBoundingSet = [ "CAP_NET_RAW" ];
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_UNIX"
        "AF_NETLINK"
      ];
      MemoryMax = "64M";
    };
  };

  networking.firewall.interfaces.${lan} = {
    allowedTCPPorts = [ port ];
    allowedUDPPorts = [ 1900 ];
  };
}
