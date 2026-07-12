{ config, pkgs, ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.loader.systemd-boot.extraInstallCommands = builtins.replaceStrings
    [ "@coreutils@" "@gnused@" ]
    [ "${pkgs.coreutils}" "${pkgs.gnused}" ]
    (builtins.readFile ./systemd-boot-generation-labels.sh);

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
    "systemd.gpt_auto=0"
  ];

  boot.blacklistedKernelModules = [ "sp5100_tco" ];

  boot.kernelModules = [ "i2c_piix4" "i2c_dev" "v4l2loopback" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
  
  boot.extraModprobeConfig = builtins.readFile ../../snippets/v4l2loopback-modprobe.conf;
}
