{ config, pkgs, inputs, ... }:

{
  imports = [
    ../../pkgs/overlays.nix
    ../../modules/core/globals.nix
    ../../modules/core/vm.nix
    ../../modules/core/persistence-vms.nix
    ../../modules/core/storage.nix
    ../../modules/core/impermanence.nix
    ../../modules/core/boot.nix
    ../../modules/core/graphics.nix
    ../../modules/core/secrets.nix
    ../../modules/core/security.nix
    ../../modules/core/ai-local.nix
    ../../modules/core/monitoring.nix
    ../../modules/core/tailscale.nix
    ../../modules/desktop/hyprland.nix
    ../../modules/desktop/sddm.nix
    ../../modules/desktop/bluetooth.nix
    ../../modules/desktop/kdeconnect.nix
    ../../modules/desktop/keyd.nix
    ../../modules/desktop/keyledsd.nix
    ../../modules/desktop/ydotool.nix
    ../../modules/desktop/openrgb.nix
    ../../modules/desktop/rival-mouse.nix
    ../../modules/desktop/seafile.nix
    ../../modules/desktop/steam.nix
    ../../modules/desktop/minecraft.nix
    ../../modules/user/home-manager.nix
    ../../modules/audits/default.nix
  ];

  mandragora.ai.agentic.enable = true;
  services.mandragora-seafile.enable = true;

  nixpkgs.hostPlatform = "x86_64-linux";
  nixpkgs.config.allowUnfree = true;

  time.timeZone = "America/Sao_Paulo";
  i18n.defaultLocale = "en_US.UTF-8";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  boot.loader.systemd-boot.configurationLimit = 10;

  system.stateVersion = "24.05";
}
