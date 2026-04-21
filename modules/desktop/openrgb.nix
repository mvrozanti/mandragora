{ pkgs, lib, ... }:
{
  services.hardware.openrgb = {
    enable = true;
    package = pkgs.openrgb-with-all-plugins;
    motherboard = "amd";
  };

  # Keep the unit defined (so `sudo systemctl start openrgb` works on demand for
  # driving RAM/motherboard LEDs), but never auto-start it at boot. openrgb's
  # HID probe on the Logitech G Pro keyboard corrupts keyleds' feature-discovery
  # state, leaving the keyboard dark. Boot-time order cannot be reliably fixed,
  # so we keep openrgb off the boot path entirely.
  systemd.services.openrgb.wantedBy = lib.mkForce [];

  hardware.i2c.enable = true;
  boot.kernelModules = [ "i2c-dev" ];
}
