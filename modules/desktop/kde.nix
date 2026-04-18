{ config, pkgs, ... }:

{
  services.desktopManager.plasma6.enable = true;

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.kdePackages.xdg-desktop-portal-kde ];
  };

  environment.systemPackages = with pkgs; [
    kdePackages.plasma-browser-integration
    kdePackages.filelight
    kdePackages.ark
  ];
}
