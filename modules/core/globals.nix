{ config, pkgs, lib, ... }:

{
  # Core Global Definitions
  networking.hostName = "mandragora";

  # Main User Definition
  users.users.m = {
    isNormalUser = true;
    description = "Mandragora Primary User";
    extraGroups = [ "networkmanager" "wheel" "video" "audio" ];
    shell = pkgs.zsh;
  };

  # Enable zsh globally so it can be set as the default shell
  programs.zsh.enable = true;

  # Essential Core Packages
  environment.systemPackages = with pkgs; [
    git
    vim
    neovim
    wget
    curl
    htop
    btop
    tree
  ];
}
