{ config, pkgs, ... }:

{
  # OpenRGB hardware control
  services.hardware.openrgb = {
    enable = true;
    package = pkgs.openrgb-with-all-plugins;
    motherboard = "amd";
  };

  # Run an OpenRGB profile on startup (e.g., setting a static color or loading a pywal generated profile)
  # You would place your openrgb profile in /home/m/.config/OpenRGB
  systemd.user.services.openrgb-apply = {
    description = "Apply OpenRGB profile on startup";
    wantedBy = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.openrgb-with-all-plugins}/bin/openrgb --profile default.orp";
      Type = "oneshot";
    };
  };
}
