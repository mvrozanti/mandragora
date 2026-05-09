{ config, pkgs, ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.loader.systemd-boot.extraInstallCommands = ''
    for entry in /boot/loader/entries/nixos-generation-*.conf; do
      [ -e "$entry" ] || continue
      gen=$(${pkgs.coreutils}/bin/basename "$entry" | ${pkgs.gnused}/bin/sed -E 's/^nixos-generation-([0-9]+).*\.conf$/\1/')
      link="/nix/var/nix/profiles/system-''${gen}-link"
      if [ -L "$link" ]; then
        ts=$(${pkgs.coreutils}/bin/stat -c %Y "$link")
        date=$(${pkgs.coreutils}/bin/date -d "@''${ts}" '+%Y-%m-%d %H:%M')
        rev=""
        if [ -r "$link/git-revision" ]; then
          rev=$(${pkgs.coreutils}/bin/head -c 7 "$link/git-revision")
        fi
        if [ -n "$rev" ]; then
          version="Generation ''${gen}, ''${rev}, ''${date}"
        else
          version="Generation ''${gen}, ''${date}"
        fi
        ${pkgs.gnused}/bin/sed -i "s|^version .*|version ''${version}|" "$entry"
      fi
    done
  '';

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
