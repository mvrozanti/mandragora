{ config, pkgs, lib, ... }:

{
  networking.hostName = "mandragora";

  users.users.m = {
    isNormalUser = true;
    description = "Mandragora Primary User";
    extraGroups = [ "networkmanager" "wheel" "video" "audio" "i2c" "plugdev" ];
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
    gemini-cli
    nodejs
    rofi
    wl-clipboard
    grim
    slurp
    wf-recorder
    playerctl
    brightnessctl
    pamixer
    mpc
    pavucontrol
    crosspipe
    cliphist
    nemo
    lf
    scrcpy
    polkit_gnome
    zoxide
    xsel
    gnumake
    gcc
    yarn
    gawk
    dmidecode
    iotop
  ];
}
