{ config, pkgs, ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.systemd.enable = true;

  boot.kernelPackages = pkgs.linuxPackages_zen;

  boot.kernelParams = [ "i2c_piix4.force=1"  "usbcore.autosuspend=-1" "usbcore.old_scheme_first=1" "acpi_enforce_resources=lax" ];

  boot.blacklistedKernelModules = [ "sp5100_tco" ];

  boot.kernelModules = [ "i2c_piix4" "i2c_dev" ];

  boot.initrd.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];
}
