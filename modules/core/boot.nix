{ config, pkgs, ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.systemd.enable = true;

  boot.kernelPackages = pkgs.linuxPackages_zen;

  boot.kernelParams = [
    "usbcore.autosuspend=-1"
    "usbcore.old_scheme_first=1"
    "acpi_enforce_resources=lax"
    "slab_nomerge"
    "init_on_alloc=0"
    "init_on_free=0"
    "randomize_kstack_offset=on"
    "vsyscall=none"
    "mitigations=off"
  ];

  boot.blacklistedKernelModules = [ "sp5100_tco" ];

  boot.kernelModules = [ "i2c_piix4" "i2c_dev" "v4l2loopback" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
  
  boot.extraModprobeConfig = ''
    options v4l2loopback devices=1 video_nr=10 card_label="DroidCam" exclusive_caps=1
  '';
}
