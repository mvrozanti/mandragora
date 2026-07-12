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
    gtk3.extraCss = ''
      window.dialog,
      window.dialog.background,
      window.dialog.csd,
      window.dialog.solid-csd,
      window.dialog decoration,
      window.dialog headerbar,
      window.dialog .titlebar,
      window.dialog box,
      window.dialog grid,
      window.dialog stack,
      window.dialog scrolledwindow,
      window.dialog viewport,
      window.dialog notebook,
      window.dialog paned,
      window.dialog paned > separator,
      filechooser,
      filechooser box,
      filechooser grid,
      filechooser stack,
      filechooser scrolledwindow,
      filechooser viewport,
      filechooser paned,
      filechooser placessidebar,
      filechooser placessidebar list,
      filechooser placessidebar list row,
      filechooser .view,
      filechooser pathbar,
      filechooser pathbar > box {
        background-color: rgba(0, 0, 0, 0.4);
        background-image: none;
      }
    '';
    gtk4.extraCss = ''
      window.dialog,
      window.dialog.background,
      window.dialog.csd,
      window.dialog headerbar,
      window.dialog .titlebar,
      window.dialog windowhandle,
      window.dialog box,
      window.dialog grid,
      window.dialog stack,
      window.dialog scrolledwindow,
      window.dialog viewport,
      window.dialog paned,
      filechooser,
      filechooser box,
      filechooser grid,
      filechooser stack,
      filechooser scrolledwindow,
      filechooser viewport,
      filechooser paned,
      filechooser placessidebar,
      filechooser placessidebar listview,
      filechooser placessidebar listview row,
      filechooser listview,
      filechooser pathbar {
        background-color: rgba(0, 0, 0, 0.4) !important;
        background-image: none !important;
      }
    '';
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
