{ config, lib, pkgs, ... }:

{
  imports = [
    ../../pkgs/overlays.nix
  ];

  mandragora.profile = "wsl";

  wsl = {
    enable = true;
    defaultUser = "m";
    startMenuLaunchers = true;
    wslConf = {
      automount.root = "/mnt";
      interop.enabled = true;
      interop.appendWindowsPath = true;
      network.generateResolvConf = true;
    };
  };

  networking.hostName = "mandragora-wsl";
  time.timeZone = "America/Sao_Paulo";
  i18n.defaultLocale = "en_US.UTF-8";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  nixpkgs.config.allowUnfree = true;

  users.users.m = {
    isNormalUser = true;
    description = "Mandragora Primary User";
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
  };

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    git
    wget
    curl
    fastfetch
    rtk
  ];

  programs.zsh.enable = true;

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.m = { lib, ... }: {
    imports = [ ../../modules/shared/home-cli.nix ];
    home.username = "m";
    home.homeDirectory = "/home/m";
    home.stateVersion = "24.05";
    programs.zsh.shellAliases = {
      nrs = lib.mkForce "sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora-wsl --impure";
    };
  };

  system.stateVersion = "24.05";
}
