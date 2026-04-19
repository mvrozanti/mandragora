{ config, pkgs, lib, ... }:

{
  networking.hostName = "mandragora";

  users.users.m = {
    isNormalUser = true;
    description = "Mandragora Primary User";
    extraGroups = [ "networkmanager" "wheel" "video" "audio" ];
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;

  programs.nix-ld.enable = true;

  environment.systemPackages = with pkgs; [
    git
    vim
    neovim
    wget
    curl
    htop
    btop
    tree
    jq
    claude-code
    nodejs
    rofi
    wl-clipboard
    grim
    slurp
    playerctl
    brightnessctl
    pamixer
    mpc
    pavucontrol
    crosspipe
  ];
}
