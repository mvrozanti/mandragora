{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    @MICROCODE_IMPORT@
  ];

  networking.hostName = "@HOSTNAME@";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  fileSystems."/" = {
    device = "/dev/disk/by-label/mandragora";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };

  hardware.enableRedistributableFirmware = true;
  @GPU_DRIVER_BLOCK@

  users.users.@USER@ = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    shell = pkgs.zsh;
    initialPassword = "mandragora";
  };

  programs.zsh.enable = true;
  networking.networkmanager.enable = true;
  services.openssh.enable = true;

  console.keyMap = "@KEYMAP@";

  system.stateVersion = "25.05";
}
