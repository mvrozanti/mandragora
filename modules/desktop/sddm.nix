{ config, pkgs, lib, ... }:
{
  services.displayManager = {
    sddm = {
      enable = true;
      wayland.enable = true;
      package = pkgs.kdePackages.sddm;
      theme = "sddm-mandragora";
      extraPackages = with pkgs.kdePackages; [
        qtsvg
        qtmultimedia
        qtvirtualkeyboard
      ];
    };
    autoLogin = {
      enable = true;
      user = "m";
    };
    defaultSession = "hyprland";
  };

  environment.systemPackages = [ pkgs.sddm-mandragora ];

  services.gnome.gnome-keyring.enable = true;
  security.pam.services.sddm.enableGnomeKeyring = true;
  security.pam.services.login.enableGnomeKeyring = true;
}
