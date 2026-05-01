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
  networking.networkmanager.wifi.powersave = false;
  networking.defaultGateway = "192.168.0.1";

  boot.kernel.sysctl = {
    "net.ipv6.conf.enp8s0.accept_ra" = 2;
    "net.ipv6.conf.enp8s0.autoconf" = 1;
  };

  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = false;
    settings = {
      server = [ "1.1.1.1" "1.0.0.1" ];
      addn-hosts = [ config.sops.templates."hosts-oracle".path ];
      listen-address = "127.0.0.1";
      bind-interfaces = true;
    };
  };

  users.users.m = {
    isNormalUser = true;
    description = "Mandragora Primary User";
    extraGroups = [ "networkmanager" "wheel" "video" "audio" "i2c" "plugdev" "ydotool" ];
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;

  programs.nix-ld.enable = true;

  programs.gpu-screen-recorder.enable = true;

  systemd.settings.Manager.DefaultTimeoutStopSec = "20s";

  environment.systemPackages = with pkgs; [
    git
    vim
    neovim
    wget
    curl
    htop
    btop
    tree
    fastfetch
    jq
    sops
    age
    gemini-cli
    rtk
    nodejs
    rofi
    wl-clipboard
    grim
    slurp
    wf-recorder
    flameshot
    eww
    jq
    playerctl
    brightnessctl
    pamixer
    pulseaudio
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
    xev
    wev
    gnumake
    gcc
    cmake
    yarn
    gawk
    dmidecode
    iotop
    dnsmasq
  ];
}
