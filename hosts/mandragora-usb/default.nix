{ config, pkgs, lib, ... }:

let
  installScripts = pkgs.runCommand "mandragora-install-scripts" { } ''
    mkdir -p $out/libexec/mandragora-install
    cp ${./install}/*.sh $out/libexec/mandragora-install/
    cp ${./install}/host-template.nix $out/libexec/mandragora-install/
    chmod +x $out/libexec/mandragora-install/*.sh
    mkdir -p $out/bin
    ln -s $out/libexec/mandragora-install/install.sh        $out/bin/mandragora-install
    ln -s $out/libexec/mandragora-install/detect.sh         $out/bin/mandragora-detect
    ln -s $out/libexec/mandragora-install/format.sh         $out/bin/mandragora-format
    ln -s $out/libexec/mandragora-install/render-config.sh  $out/bin/mandragora-render-config
  '';
in
{
  mandragora.profile = "live";

  networking.hostName = "mandragora-usb";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  nixpkgs.config.allowUnfree = true;

  time.timeZone = "America/Sao_Paulo";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  users.users.m = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    shell = pkgs.zsh;
    initialPassword = "mandragora";
  };

  users.users.root.initialPassword = "mandragora";

  programs.tmux.enable = true;
  programs.nix-ld.enable = true;

  environment.systemPackages = (with pkgs; [
    git
    sops
    age
    openssh
    networkmanager
    htop
    curl
    wget
    pciutils
    usbutils
    parted
    gptfdisk
    dosfstools
    e2fsprogs
    util-linux
    nixos-install-tools
  ]) ++ [ installScripts ];

  networking.networkmanager.enable = true;

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    settings.PasswordAuthentication = true;
  };

  hardware.enableRedistributableFirmware = true;
  hardware.enableAllHardware = true;

  boot.initrd.systemd.emergencyAccess = true;

  fileSystems."/persist" = {
    device = "/dev/disk/by-label/mandragora-persist";
    fsType = "ext4";
    options = [ "nofail" "x-systemd.device-timeout=10" ];
  };

  systemd.tmpfiles.rules = [
    "d /persist 0755 root root - -"
    "d /persist/npm-global 0755 m users - -"
  ];

  environment.etc."nixos/mandragora".source = ../..;

  system.stateVersion = "25.05";
}
