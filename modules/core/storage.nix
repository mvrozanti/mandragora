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

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  fileSystems."/mnt/toshiba" = {
    device = "/dev/disk/by-uuid/B40C6DD40C6D9262";
    fsType = "ntfs-3g";
    options = [ "noauto" "nofail" "x-systemd.automount" "x-systemd.device-timeout=5" "x-systemd.idle-timeout=300" "uid=1000" "gid=100" "remove_hiberfile" ];
  };

  fileSystems."/mnt/adata" = {
    device = "/dev/disk/by-uuid/8f573b56-3312-44b2-abcf-21b4bff1996d";
    fsType = "ext4";
    options = [ "noauto" "nofail" "x-systemd.automount" "x-systemd.device-timeout=5" "x-systemd.idle-timeout=300" ];
  };

  swapDevices = [
    { device = "/dev/disk/by-label/SWAP"; }
  ];

  # The "Erase Your Darlings" Rollback Script
  boot.initrd.systemd.services.rollback = {
    description = "Rollback BTRFS root subvolume to a pristine state";
    wantedBy = [ "initrd.target" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /mnt
      
      # Mount the btrfs root
      mount -o subvol=/ /dev/disk/by-label/NIXOS /mnt
      
      # Delete current root-active if it exists
      if [ -e "/mnt/root-active" ]; then
          btrfs subvolume delete -c "/mnt/root-active"
      fi
      
      # Snapshot the blank seed (assuming we create a seed at install/shutdown)
      # For now, we snapshot a 'root-blank' subvolume if it exists, or create a new empty one
      if [ -e "/mnt/root-blank" ]; then
          btrfs subvolume snapshot "/mnt/root-blank" "/mnt/root-active"
      else
          btrfs subvolume create "/mnt/root-active"
      fi
      
      umount /mnt
    '';
  };
}
