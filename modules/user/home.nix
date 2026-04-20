{ config, pkgs, ... }:

let
  smart-launch = pkgs.writeShellScript "smart-launch" (builtins.readFile ../../snippets/smart-launch.sh);
  rofi-ide-picker = pkgs.writeShellScript "rofi-ide-picker" (builtins.readFile ../../snippets/rofi-ide-picker.sh);
  rofi-tool-picker = pkgs.writeShellScript "rofi-tool-picker" (builtins.readFile ../../snippets/rofi-tool-picker.sh);
  rofi-db-picker = pkgs.writeShellScript "rofi-db-picker" (builtins.readFile ../../snippets/rofi-db-picker.sh);
in
{
  imports = [
    ./zsh.nix
    ./tmux.nix
    ./lf.nix
  ];

  home.username = "m";
  home.homeDirectory = "/home/m";
  home.stateVersion = "23.11";

  # Packages that should be installed to the user profile.
  home.packages = with pkgs; [
    # Utils
    ripgrep
    fd
    fzf
    jq
    bat
    eza
    htop
    btop
    trash-cli
    unzip
    unp
    atool
    file
    tree
    
    # Media
    mpv
    sxiv
    zathura
    imagemagick
    ffmpegthumbnailer
    
    # Tools
    git
    gh
    gh-dash
    neovim
    python3
    zoxide
    
    # Custom scripts
    (pkgs.writeShellScriptBin "smart-launch" (builtins.readFile ../../snippets/smart-launch.sh))
    (pkgs.writeShellScriptBin "rofi-ide-picker" (builtins.readFile ../../snippets/rofi-ide-picker.sh))
    (pkgs.writeShellScriptBin "rofi-tool-picker" (builtins.readFile ../../snippets/rofi-tool-picker.sh))
    (pkgs.writeShellScriptBin "rofi-db-picker" (builtins.readFile ../../snippets/rofi-db-picker.sh))
  ];

  # Session Variables
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    BROWSER = "firefox";
    
    # Cedilla and Accents
    GTK_IM_MODULE = "cedilla";
    QT_IM_MODULE = "cedilla";
    XMODIFIERS = "@im=cedilla";
    
    # Global Font Scaling / DPI
    GDK_DPI_SCALE = "1.0";
    QT_AUTO_SCREEN_SCALE_FACTOR = "1";
    QT_ENABLE_HIGHDPI_SCALING = "1";
  };

  # GTK Configuration
  gtk = {
    enable = true;
    font = {
      name = "Iosevka Nerd Font";
      size = 11;
    };
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
  };

  # Kitty Configuration
  programs.kitty = {
    enable = true;
    font = {
      name = "Iosevka Nerd Font Mono";
      size = 11.5;
    };
    settings = {
      cursor = "#cccccc";
      cursor_text_color = "#111111";
      cursor_shape = "block";
      scrollback_lines = 2000;
      url_color = "#0087BD";
      url_style = "curly";
      repaint_delay = 16;
      input_delay = 6;
      sync_to_monitor = "no";
      enable_audio_bell = "yes";
      remember_window_size = "yes";
      initial_window_width = 640;
      initial_window_height = 400;
      window_border_width = "1.0";
      draw_minimal_borders = "yes";
      active_border_color = "#00ff00";
      inactive_border_color = "#cccccc";
      tab_bar_style = "fade";
      foreground = "#dddddd";
      background = "#000";
      background_opacity = "1.0";
      allow_remote_control = "yes";
      listen_on = "unix:@kitty";
      term = "xterm-kitty";
    };
    keybindings = {
      "ctrl+shift+c" = "copy_to_clipboard";
      "ctrl+shift+v" = "paste_from_clipboard";
      "ctrl+shift+s" = "paste_from_selection";
      "shift+insert" = "paste_from_selection";
      "ctrl+shift+up" = "scroll_line_up";
      "ctrl+shift+k" = "scroll_line_up";
      "ctrl+shift+down" = "scroll_line_down";
      "ctrl+shift+j" = "scroll_line_down";
      "ctrl+shift+page_up" = "scroll_page_up";
      "ctrl+shift+page_down" = "scroll_page_down";
      "ctrl+shift+home" = "scroll_home";
      "ctrl+shift+end" = "scroll_end";
      "ctrl+shift+h" = "show_scrollback";
      "ctrl+alt+k" = "send_text all \\x1b[A";
      "ctrl+alt+j" = "send_text all \\x1b[B";
      "ctrl+shift+n" = "new_os_window";
      "ctrl+shift+]" = "next_window";
      "ctrl+shift+[" = "previous_window";
      "ctrl+shift+f" = "move_window_forward";
      "ctrl+shift+b" = "move_window_backward";
      "ctrl+shift+right" = "next_tab";
      "ctrl+shift+left" = "previous_tab";
      "ctrl+shift+t" = "new_tab";
      "ctrl+shift+l" = "next_layout";
      "ctrl+k" = "change_font_size all +1.0";
      "ctrl+j" = "change_font_size all -1.0";
      "ctrl+0" = "change_font_size all 0";
    };
  };

  # Hyprland
  wayland.windowManager.hyprland = {
    enable = true;
    extraConfig = builtins.readFile ../../snippets/hyprland.conf;
  };

  # Services
  services.mako.enable = true;
  
  # Programs
  programs.home-manager.enable = true;
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  home.file.".XCompose".source = ../../snippets/XCompose;
}
