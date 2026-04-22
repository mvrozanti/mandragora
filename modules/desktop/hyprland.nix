{ config, pkgs, ... }:
{
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  services.xserver.xkb.options = "caps:swapescape";

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    LIBVA_DRIVER_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    XDG_SESSION_TYPE = "wayland";
    AQ_DRM_DEVICES = "/dev/dri/card1";
    
    # Cedilla and Accents
    GTK_IM_MODULE = "cedilla";
    QT_IM_MODULE = "cedilla";
    XMODIFIERS = "@im=cedilla";
  };

  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
    ];
    config.common.default = "*";
  };

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    wireplumber = {
      enable = true;
      configPackages = [
        (pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/99-hdmi-default.conf"
          (builtins.readFile ../../.config/wireplumber/hdmi-default.conf))
      ];
    };
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  fonts.packages = with pkgs; [
    nerd-fonts.iosevka
    font-awesome
    noto-fonts
    noto-fonts-color-emoji
  ];

  fonts.fontconfig.defaultFonts = {
    sansSerif = [ "Noto Sans" ];
    serif = [ "Noto Serif" ];
    monospace = [ "Iosevka Nerd Font Mono" ];
    emoji = [ "Noto Color Emoji" ];

  };
}
