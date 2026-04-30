{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot";

  boot.kernelParams = [
    "console=ttyAMA0,115200"
    "console=tty0"
    "ip=dhcp"
    "rd.iscsi.param=node.session.timeo.replacement_timeout=6000"
    "rd.net.timeout.dhcp=10"
    "rd.net.timeout.carrier=5"
    "net.ifnames=1"
    "nvme_core.shutdown_timeout=10"
  ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "virtio_pci"
    "virtio_scsi"
    "sd_mod"
    "sr_mod"
    "iscsi_tcp"
    "libiscsi"
    "scsi_transport_iscsi"
  ];
  boot.initrd.kernelModules = [ "iscsi_tcp" ];
  boot.initrd.network.enable = true;
  boot.initrd.services.lvm.enable = true;

  boot.initrd.services.iscsi = {
    enable = true;
    targets = [{
      name = "iqn.2015-02.oracle.boot:uefi";
      ip = "169.254.0.2";
    }];
    initiatorName = "iqn.1988-12.com.oracle:abcdef0123456789";
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos-root";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/EFI";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  swapDevices = [ ];

  networking.useDHCP = lib.mkDefault true;
  networking.interfaces.enp0s6.useDHCP = lib.mkDefault true;

  hardware.enableRedistributableFirmware = true;
}
