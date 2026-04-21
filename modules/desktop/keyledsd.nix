{ pkgs, ... }:

let
  keyleds-patched = pkgs.keyleds.overrideAttrs (old: {
    patches = (old.patches or []) ++ [ ./keyleds-xwayland.patch ];
  });
in
{
  environment.systemPackages = [ keyleds-patched ];

  services.udev.packages = [ keyleds-patched ];

  # keyledsd runs as the user service; give the logged-in seat write access to
  # the Logitech G Pro keyboard's hidraw node. nixpkgs' keyleds package ships
  # no udev rules, so /dev/hidraw* is root-only by default.
  services.udev.extraRules = ''
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="c339", MODE="0660", TAG+="uaccess"
  '';

  systemd.user.services.keyledsd = {
    description = "Keyleds RGB keyboard daemon";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${keyleds-patched}/bin/keyledsd -m ${keyleds-patched}/lib/keyledsd -m ${keyleds-patched}/share/keyledsd/effects";
      Restart = "on-failure";
      RestartSec = "3s";
    };
  };
}
