{ config, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix

    ../../modules/core/secrets.nix

    ../../modules/vps/oci.nix
    ../../modules/vps/tailscale.nix
    ../../modules/vps/ddns.nix
    ../../modules/vps/seafile.nix
    ../../modules/vps/hummingbot.nix
    ../../modules/vps/crypto-fetcher.nix
    ../../modules/vps/orderbook-collector.nix
  ];

  networking.hostName = "mandragora-vps";

  nixpkgs.hostPlatform = "aarch64-linux";
  nixpkgs.config.allowUnfree = true;

  time.timeZone = "America/Sao_Paulo";
  i18n.defaultLocale = "en_US.UTF-8";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  users.users.m = {
    isNormalUser = true;
    description = "Mandragora Primary User";
    extraGroups = [ "wheel" "docker" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDUMYP05r/uKioMR0990Q8ql4fb8pvJz3WjvqJ0ytw5RhvFAPgystANW9YBtNWfRgp8LJWKaoNBH5S0YKPgaY4Kla7AbAEHvEKO8Ci+mPfSRfSWT/Lk8b2FyqU+H7eJ1Iu1NfRgKkOE2SsX0sj0hrOFmR7pjpdzyLiOP7EzrjoMhFVGB5BmSb+gQXFG2E9q7A4CHfEalpx+sxG4DSl1z4o+2LRVMkaZRApjCrf84P85E84/ol/RmMHE4DCEdxLHUyEU3xCFTahW1g4pcPrnXbtr7htpgs3FoxmFFppHPYC5s7z35OrlEmOVjsR642tVS6NlUH4CKTosbJ1+OZv+jYO9 mvrozanti@hotmail.com"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  programs.zsh.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };

  environment.systemPackages = with pkgs; [
    git vim neovim wget curl htop btop tree jq sops age
    rsync tmux file
  ];

  system.stateVersion = "24.05";
}
