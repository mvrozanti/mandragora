{ pkgs, ... }:

{
  boot.supportedFilesystems = [
    "ntfs"
    "exfat"
  ];

  services.udisks2.enable = true;
  # Create /media as a symlink to /mnt so that udisks2 shared mounts (UDISKS_FILESYSTEM_SHARED=1)
  # appear under /mnt as requested.
  systemd.tmpfiles.rules = [
    "L+ /media - - - - /mnt"
  ];

  services.udev.extraRules = builtins.readFile ../../snippets/udisks-shared-mounts.rules;
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS";
    fsType = "btrfs";
    options = [
      "subvol=root-active"
      "compress=zstd:1"
      "noatime"
      "ssd"
      "discard=async"
      "space_cache=v2"
    ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-label/NIXOS";
    fsType = "btrfs";
    options = [
      "subvol=nix"
      "compress=zstd:1"
      "noatime"
      "ssd"
      "discard=async"
      "space_cache=v2"
    ];
  };

  fileSystems."/persistent" = {
    device = "/dev/disk/by-label/NIXOS";
    fsType = "btrfs";
    options = [
      "subvol=persistent"
      "compress=zstd:1"
      "noatime"
      "ssd"
      "discard=async"
      "space_cache=v2"
    ];
    neededForBoot = true;
  };

  fileSystems."/home/m/Games" = {
    device = "/dev/disk/by-label/NIXOS";
    fsType = "btrfs";
    options = [
      "subvol=games"
      "compress=zstd:1"
      "noatime"
      "ssd"
      "discard=async"
      "space_cache=v2"
    ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  fileSystems."/mnt/toshiba" = {
    device = "/dev/disk/by-uuid/14fdc735-6642-4688-b0b3-1deb3170490e";
    fsType = "ext4";
    options = [
      "noauto"
      "nofail"
      "x-systemd.automount"
      "x-systemd.device-timeout=5"
      "x-systemd.idle-timeout=300"
    ];
  };

  fileSystems."/mnt/sandisk" = {
    device = "/dev/disk/by-uuid/f892fa0d-ce81-4137-bf64-5a1a40a8c4b1";
    fsType = "ext4";
    options = [
      "noauto"
      "nofail"
      "x-systemd.automount"
      "x-systemd.device-timeout=5"
      "x-systemd.idle-timeout=300"
    ];
  };
  fileSystems."/mnt/adata" = {
    device = "/dev/disk/by-uuid/8f573b56-3312-44b2-abcf-21b4bff1996d";
    fsType = "ext4";
    options = [
      "noauto"
      "nofail"
      "x-systemd.automount"
      "x-systemd.device-timeout=5"
      "x-systemd.idle-timeout=300"
    ];
  };

  swapDevices = [
    {
      device = "/dev/disk/by-partlabel/SWAP";
      priority = 1;
    }
  ];

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
    priority = 100;
  };

  boot.initrd.systemd.storePaths = [
    "${pkgs.util-linux}/bin/mount"
    "${pkgs.util-linux}/bin/umount"
    "${pkgs.btrfs-progs}/bin/btrfs"
    "${pkgs.gawk}/bin/awk"
    "${pkgs.coreutils}/bin/mkdir"
  ];

  boot.initrd.systemd.services.rollback = {
    description = "Rollback BTRFS root subvolume to a pristine state";
    wantedBy = [ "initrd.target" ];
    after = [ "initrd-root-device.target" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script =
      builtins.replaceStrings
        [ "@mkdir@" "@mount@" "@umount@" "@btrfs@" "@awk@" ]
        [
          "${pkgs.coreutils}/bin/mkdir"
          "${pkgs.util-linux}/bin/mount"
          "${pkgs.util-linux}/bin/umount"
          "${pkgs.btrfs-progs}/bin/btrfs"
          "${pkgs.gawk}/bin/awk"
        ]
        (builtins.readFile ./initrd-rollback.sh);
  };
}
