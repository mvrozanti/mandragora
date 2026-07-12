{
  config,
  lib,
  pkgs,
  ...
}:

{
  home.username = "m";
  home.homeDirectory = "/home/m";
  home.stateVersion = "23.11";

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    BROWSER = "firefox";
    GOPATH = "${config.home.homeDirectory}/.local/share/go";
    GOBIN = "${config.home.homeDirectory}/.local/share/go/bin";
    GDK_DPI_SCALE = "1.0";
    QT_AUTO_SCREEN_SCALE_FACTOR = "1";
    QT_ENABLE_HIGHDPI_SCALING = "1";
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_QPA_PLATFORMTHEME = lib.mkForce "gnome";
    WALLPAPER_DIR = "${config.home.homeDirectory}/Pictures/wllpps";
  };

  home.sessionPath = [
    "${config.home.homeDirectory}/.local/share/go/bin"
  ];

  home.pointerCursor = {
    name = "Bibata-Modern-Classic";
    package = pkgs.bibata-cursors;
    size = 24;
    gtk.enable = true;
    x11.enable = true;
    hyprcursor.enable = true;
  };
}
