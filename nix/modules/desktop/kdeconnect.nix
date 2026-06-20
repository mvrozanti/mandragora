{ pkgs, ... }:
let
  hypr-kdeconnect-portal = pkgs.callPackage ../../pkgs/hypr-kdeconnect-portal { };
in
{
  programs.kdeconnect = {
    enable = true;
    package = pkgs.kdePackages.kdeconnect-kde;
  };

  xdg.portal.extraPortals = [ hypr-kdeconnect-portal ];
  xdg.portal.config.common."org.freedesktop.impl.portal.RemoteDesktop" = [ "hypr-kdeconnect" ];
  systemd.packages = [ hypr-kdeconnect-portal ];
  services.dbus.packages = [ hypr-kdeconnect-portal ];

  systemd.user.services.kdeconnectd = {
    description = "KDE Connect daemon";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.kdePackages.kdeconnect-kde}/bin/kdeconnectd";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
