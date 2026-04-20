{ config, pkgs, ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.systemd.enable = true;

  boot.kernelPackages = pkgs.linuxPackages_zen;

  boot.kernelParams = [ "sp5100_tco.nowayout=1" "usbcore.autosuspend=-1" "usbcore.old_scheme_first=1" ];

  boot.initrd.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];
}
