{ config, lib, pkgs, ... }:

{
  boot.supportedFilesystems = [ "ntfs" ];
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS";
    fsType = "btrfs";
    options = [ "subvol=root-active" "compress=zstd:1" "noatime" "ssd" "space_cache=v2" ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-label/NIXOS";
    fsType = "btrfs";
    options = [ "subvol=nix" "compress=zstd:1" "noatime" "ssd" "space_cache=v2" ];
  };

  fileSystems."/persistent" = {
    device = "/dev/disk/by-label/NIXOS";
    fsType = "btrfs";
    options = [ "subvol=persistent" "compress=zstd:1" "noatime" "ssd" "space_cache=v2" ];
    neededForBoot = true;
  };

  fileSystems."/home/m/Games" = {
    device = "/dev/disk/by-label/NIXOS";
    fsType = "btrfs";
    options = [ "subvol=games" "compress=zstd:1" "noatime" "ssd" "space_cache=v2" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  fileSystems."/mnt/toshiba" = {
    device = "/dev/disk/by-uuid/14fdc735-6642-4688-b0b3-1deb3170490e";
    fsType = "ext4";
    options = [ "noauto" "nofail" "x-systemd.automount" "x-systemd.device-timeout=5" "x-systemd.idle-timeout=300" ];
  };

  fileSystems."/mnt/adata" = {
    device = "/dev/disk/by-uuid/8f573b56-3312-44b2-abcf-21b4bff1996d";
    fsType = "ext4";
    options = [ "noauto" "nofail" "x-systemd.automount" "x-systemd.device-timeout=5" "x-systemd.idle-timeout=300" ];
  };

  swapDevices = [
    { device = "/dev/disk/by-label/SWAP"; }
  ];

  boot.resumeDevice = "/dev/disk/by-uuid/35f1250b-3b82-45bb-abab-62236e91fe26";

  boot.initrd.systemd.services.rollback = {
    description = "Rollback BTRFS root subvolume to a pristine state";
    wantedBy = [ "initrd.target" ];
    after = [ "initrd-root-device.target" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    path = [ pkgs.gawk pkgs.btrfs-progs pkgs.util-linux pkgs.coreutils ];
    script = ''
      mkdir -p /mnt

      # -t btrfs required: initrd mount cannot auto-detect filesystem type
      mount -t btrfs -o subvol=/ /dev/disk/by-label/NIXOS /mnt

      # Delete nested subvols first (systemd creates these on every successful boot)
      if [ -e "/mnt/root-active" ]; then
          subvols=$(btrfs subvolume list -o /mnt/root-active | awk '{print $NF}')
          for subvol in $subvols; do
              btrfs subvolume delete "/mnt/$subvol"
          done
          btrfs subvolume delete -c "/mnt/root-active"
      fi

      if [ -e "/mnt/root-blank" ]; then
          btrfs subvolume snapshot "/mnt/root-blank" "/mnt/root-active"
      else
          btrfs subvolume create "/mnt/root-active"
      fi

      umount /mnt
    '';
  };
}
