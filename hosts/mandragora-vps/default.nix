{ config, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix

    ../../modules/core/globals.nix
    ../../modules/core/secrets.nix
    ../../modules/core/security.nix

    ../../modules/vps/oci.nix
    ../../modules/vps/tailscale.nix
    ../../modules/vps/ddns.nix
    ../../modules/vps/seafile.nix
    ../../modules/vps/openvpn.nix
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
    extraGroups = [ "wheel" "docker" ];
    openssh.authorizedKeys.keys = config.mandragora.globals.sshKeys or [ ];
  };

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

  system.stateVersion = "24.05";
}
