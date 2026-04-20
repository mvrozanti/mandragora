{ pkgs, lib, ... }:

let
  keyleds-patched = pkgs.keyleds.overrideAttrs (old: {
    patches = (old.patches or []) ++ [ ./keyleds-xwayland.patch ];
  });
in
{
  environment.systemPackages = [ keyleds-patched ];

  services.udev.packages = [ keyleds-patched ];

  systemd.user.services.keyledsd = {
    description = "Keyleds RGB keyboard daemon";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${keyleds-patched}/bin/keyledsd -m ${keyleds-patched}/lib/keyledsd";
      Restart = "on-failure";
      RestartSec = "3s";
    };
  };
}
