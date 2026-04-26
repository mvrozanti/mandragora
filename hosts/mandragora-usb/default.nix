{ config, pkgs, lib, ... }:

{
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

  programs.zsh.enable = true;
  programs.tmux.enable = true;
  programs.nix-ld.enable = true;

  environment.systemPackages = with pkgs; [
    git
    neovim
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
  ];

  networking.networkmanager.enable = true;
  networking.wireless.enable = false;

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    settings.PasswordAuthentication = true;
  };

  hardware.enableRedistributableFirmware = true;

  system.stateVersion = "25.05";
}
