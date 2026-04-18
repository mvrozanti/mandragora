{ config, pkgs, inputs, ... }:

{
  imports = [
    ../../modules/core/globals.nix
    ../../modules/core/storage.nix
    ../../modules/core/impermanence.nix
    ../../modules/core/boot.nix
    ../../modules/core/graphics.nix
    ../../modules/core/secrets.nix
    ../../modules/desktop/hyprland.nix
    ../../modules/desktop/rgb.nix
    ../../modules/desktop/seafile.nix
    ../../modules/user/home-manager.nix
    ../../modules/audits/default.nix
  ];

  # System Architecture
  nixpkgs.hostPlatform = "x86_64-linux";

  # Timezone and Locale
  time.timeZone = "America/Sao_Paulo";
  i18n.defaultLocale = "en_US.UTF-8";

  # Nix configuration
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  boot.loader.systemd-boot.configurationLimit = 10;

  # System state version (Do not change lightly)
  system.stateVersion = "24.05";
}
