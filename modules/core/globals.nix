{ config, pkgs, lib, ... }:

{
  networking.hostName = "mandragora";

  networking.useDHCP = false;
  networking.interfaces.enp8s0 = {
    useDHCP = false;
    ipv4.addresses = [{ address = "192.168.0.27"; prefixLength = 24; }];
    tempAddress = "default";
  };
  networking.interfaces.wlp7s0.useDHCP = true;
  networking.defaultGateway = "192.168.0.1";
  networking.hosts = {
    "REDACTED" = [ "oracle" ];
  };

  boot.kernel.sysctl = {
    "net.ipv6.conf.enp8s0.accept_ra" = 2;
    "net.ipv6.conf.enp8s0.autoconf" = 1;
  };

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
    sops
    age
    # claude-code  # broken in nixpkgs 2.1.116 (cli.js missing), installed via npm
    gemini-cli
    rtk
    nodejs
    rofi
    wl-clipboard
    grim
    slurp
    wf-recorder
    gpu-screen-recorder
    flameshot
    eww
    jq
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
    xorg.xev
    wev
    gnumake
    gcc
    cmake
    yarn
    gawk
    dmidecode
    iotop
  ];
}
