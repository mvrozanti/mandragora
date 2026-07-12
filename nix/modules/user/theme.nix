{ config, pkgs, ... }:

{
  gtk = {
    enable = true;
    font = {
      name = "Noto Sans";
      size = 11;
    };
    theme = {
      name = "Materia-dark";
      package = pkgs.materia-theme-transparent;
    };
    gtk4.theme = config.gtk.theme;
    iconTheme = {
      name = "breeze-dark";
      package = pkgs.kdePackages.breeze-icons;
    };
    gtk3.extraCss = builtins.readFile ../../snippets/gtk3-dialog-transparency.css;
    gtk4.extraCss = builtins.readFile ../../snippets/gtk4-dialog-transparency.css;
  };

  qt = {
    enable = true;
    platformTheme.name = "gnome";
    style.name = "adwaita-dark";
  };

  dconf.settings = {
    "org/nemo/window-state" = {
      start-with-menu-bar = false;
    };
  };
}
