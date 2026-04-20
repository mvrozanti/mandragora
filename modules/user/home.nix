{ config, pkgs, ... }:

let
  smart-launch = pkgs.writeShellScript "smart-launch" (builtins.readFile ../../.local/bin/smart-launch.sh);
  rofi-ide-picker = pkgs.writeShellScript "rofi-ide-picker" (builtins.readFile ../../.local/bin/rofi-ide-picker.sh);
  rofi-tool-picker = pkgs.writeShellScript "rofi-tool-picker" (builtins.readFile ../../.local/bin/rofi-tool-picker.sh);
  rofi-db-picker = pkgs.writeShellScript "rofi-db-picker" (builtins.readFile ../../.local/bin/rofi-db-picker.sh);
  cycle-audio-output = pkgs.writeShellScript "cycle-audio-output" (builtins.readFile ../../.local/bin/cycle-audio-output.sh);
  window-to-corner = pkgs.writeShellScript "window-to-corner" (builtins.readFile ../../.local/bin/window-to-corner.sh);

  pyDictEnv = pkgs.python3.withPackages (ps: with ps; [ requests beautifulsoup4 lxml ]);
  pySinonEnv = pkgs.python3.withPackages (ps: with ps; [ requests beautifulsoup4 lxml unidecode ]);
in
{
  imports = [
    ./zsh.nix
    ./tmux.nix
    ./lf.nix
    ./services.nix
    ./waybar.nix
  ];

  home.username = "m";
  home.homeDirectory = "/home/m";
  home.stateVersion = "23.11";

  home.packages = with pkgs; [
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
    isync
    transmission_4
    libnotify

    mpv
    sxiv
    zathura
    imagemagick
    ffmpeg
    ffmpegthumbnailer
    psmisc
    awww

    git
    gh
    gh-dash
    neovim
    (python3.withPackages (ps: with ps; [ pynvim grip psutil ]))
    zoxide
    gnupg

    ncmpcpp

    gdb
    go
    cargo
    rustc
    maven
    shellcheck
    universal-ctags
    tokei
    meson
    git-lfs
    upx
    kubectl
    mediainfo
    img2pdf
    asciidoc
    biber

    nmap
    radare2
    valgrind
    nasm
    sqlmap
    binwalk
    steghide
    gocryptfs
    bettercap
    aflplusplus
    p7zip
    ddrescue

    socat
    sshfs
    rclone
    rsync
    traceroute
    torsocks
    proxychains
    iftop
    iptraf-ng
    ipcalc
    vnstat
    whois

    figlet
    lolcat
    tig
    most
    pv
    parallel
    lynx
    ack
    translate-shell
    glances
    inxi
    fdupes
    ncdu
    lsof
    urlscan
    inotify-tools
    rmlint
    newsboat
    irssi
    silver-searcher

    gptfdisk
    gparted
    nvtopPackages.nvidia
    pass
    macchanger
    gnuplot
    taskwarrior3

    vlc
    inkscape
    gifsicle
    yt-dlp
    streamlink
    retroarch

    khal
    calcurse
    clisp
    php
    tldr
    gucharmap
    baobab
    nnn
    yq
    pdfgrep
    sqlitebrowser
    libreoffice
    lazygit
    pueue
    gource
    mkvtoolnix
    jiq

    telegram-desktop
    discord
    spotify
    obsidian
    zapzap
    tradingview
    openrgb

    (pkgs.writeShellScriptBin "smart-launch" (builtins.readFile ../../.local/bin/smart-launch.sh))
    (pkgs.writeShellScriptBin "mandragora-switch" (builtins.readFile ../../.local/bin/mandragora-switch.sh))
    (pkgs.writeShellScriptBin "rofi-ide-picker" (builtins.readFile ../../.local/bin/rofi-ide-picker.sh))
    (pkgs.writeShellScriptBin "rofi-tool-picker" (builtins.readFile ../../.local/bin/rofi-tool-picker.sh))
    (pkgs.writeShellScriptBin "rofi-db-picker" (builtins.readFile ../../.local/bin/rofi-db-picker.sh))
    (pkgs.writeShellScriptBin "cycle-audio-output" (builtins.readFile ../../.local/bin/cycle-audio-output.sh))
    (pkgs.writeShellScriptBin "window-to-corner" (builtins.readFile ../../.local/bin/window-to-corner.sh))
    (pkgs.writeShellScriptBin "gap-adjust" (builtins.readFile ../../.local/bin/gap-adjust.sh))
    (pkgs.writeShellScriptBin "opacity-adjust" (builtins.readFile ../../.local/bin/opacity-adjust.sh))
    (pkgs.writeShellScriptBin "rofi-wallpaper-picker" (builtins.readFile ../../.local/bin/rofi-wallpaper-picker.sh))
    (pkgs.writeShellScriptBin "compv" (builtins.readFile ../../.local/bin/compv.sh))
    (pkgs.writeShellScriptBin "ic" (builtins.readFile ../../.local/bin/ic.sh))
    (pkgs.writeShellScriptBin "setbg" (builtins.readFile ../../.local/bin/setbg.sh))
    (pkgs.writeShellScriptBin "make-disk-space" (builtins.readFile ../../.local/bin/make-disk-space.sh))
    (pkgs.writeShellScriptBin "gmp" (builtins.readFile ../../.local/bin/gmp.sh))
    (pkgs.writeShellScriptBin "mkv2gif" (builtins.readFile ../../.local/bin/mkv2gif.sh))
    (pkgs.writeShellScriptBin "mov2gif" (builtins.readFile ../../.local/bin/mov2gif.sh))
    (pkgs.writeShellScriptBin "mp42gif" (builtins.readFile ../../.local/bin/mp42gif.sh))
    (pkgs.writeShellScriptBin "roman" (builtins.readFile ../../.local/bin/roman.sh))
    (pkgs.writeShellScriptBin "lipsum" (builtins.readFile ../../.local/bin/lipsum.sh))
    (pkgs.writeShellScriptBin "wiki" (builtins.readFile ../../.local/bin/wiki.sh))
    (pkgs.writeShellScriptBin "after" (builtins.readFile ../../.local/bin/after.sh))
    (pkgs.writeShellScriptBin "are-processes-related" (builtins.readFile ../../.local/bin/are-processes-related.sh))
    (pkgs.writeShellScriptBin "explode_tmux" (builtins.readFile ../../.local/bin/explode_tmux.sh))
    (pkgs.writeShellScriptBin "implode_tmux" (builtins.readFile ../../.local/bin/implode_tmux.sh))
    (pkgs.writeShellScriptBin "superscript" ''exec ${pkgs.python3}/bin/python3 ${../../.local/bin/superscript.py} "$@"'')
    (pkgs.writeShellScriptBin "vaporscript" ''exec ${pkgs.python3}/bin/python3 ${../../.local/bin/vaporscript.py} "$@"'')
    (pkgs.writeShellScriptBin "cursivescript" ''exec ${pkgs.python3}/bin/python3 ${../../.local/bin/cursivescript.py} "$@"'')
    (pkgs.writeShellScriptBin "dict" ''exec ${pyDictEnv}/bin/python3 ${../../.local/bin/dict.py} "$@"'')
    (pkgs.writeShellScriptBin "sinon" ''exec ${pySinonEnv}/bin/python3 ${../../.local/bin/sinon.py} "$@"'')
    (pkgs.writeShellScriptBin "biggest-pane" (builtins.readFile ../../.local/bin/biggest-pane.sh))
    (pkgs.writeShellScriptBin "desktop-toggle" (builtins.readFile ../../.local/bin/desktop-toggle.sh))
    (pkgs.writeShellScriptBin "screenshot-window" (builtins.readFile ../../.local/bin/screenshot-window.sh))
  ];

  home.file.".local/bin/resty".source = ../../.local/bin/resty;

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    BROWSER = "firefox";
    GTK_IM_MODULE = "cedilla";
    QT_IM_MODULE = "cedilla";
    XMODIFIERS = "@im=cedilla";
    GDK_DPI_SCALE = "1.0";
    QT_AUTO_SCREEN_SCALE_FACTOR = "1";
    QT_ENABLE_HIGHDPI_SCALING = "1";
  };

  gtk = {
    enable = true;
    font = {
      name = "Noto Sans";
      size = 11;
    };
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
  };

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
      background_opacity = "0.88";
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
      "ctrl+shift+q" = "no_op";
      "ctrl+shift+l" = "next_layout";
      "ctrl+k" = "change_font_size all +1.0";
      "ctrl+j" = "change_font_size all -1.0";
      "ctrl+0" = "change_font_size all 0";
    };
  };

  wayland.windowManager.hyprland = {
    enable = true;
    settings = {
      exec-once = [
        "awww-daemon"
        "waybar"
        "wl-paste --watch cliphist store"
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
        "kdeconnect-indicator"
      ];
    };
    extraConfig = builtins.readFile ../../.config/hypr/hyprland.conf;
  };

  services.mako.enable = true;

  programs.firefox = {
    enable = true;
    nativeMessagingHosts = [ pkgs.tridactyl-native ];
  };

  programs.home-manager.enable = true;
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  home.file.".XCompose".source = ../../.XCompose;
  home.file.".config/nvim" = {
    source = ../../.config/nvim;
    recursive = true;
  };
  home.file.".config/ncmpcpp" = {
    source = ../../.config/ncmpcpp;
    recursive = true;
  };
  home.file.".config/zathura" = {
    source = ../../.config/zathura;
    recursive = true;
  };
  home.file.".config/mpv" = {
    source = ../../.config/mpv;
    recursive = true;
  };
  home.file.".config/rofi" = {
    source = ../../.config/rofi;
    recursive = true;
  };
  home.file.".config/tridactyl" = {
    source = ../../.config/tridactyl;
    recursive = true;
  };
  home.file.".config/keyledsd.conf".source = ../../.config/keyledsd/keyledsd.conf;
}
