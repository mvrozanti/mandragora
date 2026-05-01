{ config, lib, pkgs, ... }:

let
  pyDictEnv = pkgs.python3.withPackages (ps: with ps; [ requests beautifulsoup4 lxml ]);
  pySinonEnv = pkgs.python3.withPackages (ps: with ps; [ requests beautifulsoup4 lxml unidecode ]);
  hidWrapperEnv = pkgs.python3.withPackages (ps: [
    ps.colour
    (pkgs.python3.pkgs.toPythonModule pkgs.rivalcfg)
  ]);
  lightEnv = pkgs.python3.withPackages (ps: with ps; [ requests numpy ]);
  walToRgbEnv = pkgs.python3.withPackages (ps: with ps; [ openrgb-python ]);
in
{
  imports = [
    ./zsh.nix
    ./tmux.nix
    ./lf.nix
    ./services.nix
    ./bots.nix
    ./waybar.nix
    ./minecraft.nix
    ./skills.nix
  ];

  home.username = "m";
  home.homeDirectory = "/home/m";
  home.stateVersion = "23.11";

  home.packages = with pkgs; [
    ripgrep
    fd
    fzf
    uv
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
    (pkgs.symlinkJoin {
      name = "isync-xoauth2";
      paths = [ pkgs.isync ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/mbsync \
          --set SASL_PATH ${pkgs.cyrus_sasl}/lib/sasl2:${pkgs.cyrus-sasl-xoauth2}/lib/sasl2
      '';
    })
    neomutt
    msmtp
    mutt-wizard
    transmission_4
    libnotify

    mpv
    (pkgs.nsxiv.overrideAttrs (oldAttrs: {
      patches = (oldAttrs.patches or []) ++ [ ../../pkgs/nsxiv/commands.patch ];
      postPatch = (oldAttrs.postPatch or "") + "cp ${../../pkgs/nsxiv/config.h} config.def.h";
    }))
    ueberzugpp
    zathura
    imagemagick
    ffmpeg
    ffmpegthumbnailer
    psmisc
    awww

    gh-dash
    neovim
    (python3.withPackages (ps: with ps; [ pynvim grip psutil ]))
    zoxide
    gnupg

    (ncmpcpp.override { visualizerSupport = true; })

    gdb
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
    prismlauncher
    remmina
    freerdp

    khal
    cava
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
    (pkgs.symlinkJoin {
      name = "vesktop";
      paths = [ pkgs.vesktop ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/vesktop \
          --unset NIXOS_OZONE_WL \
          --unset WAYLAND_DISPLAY \
          --add-flags "--ozone-platform=x11"
      '';
    })
    obs-studio
    spotify
    obsidian
    zapzap
    gnome-chess
    tradingview
    openrgb
    matugen
    adwaita-qt
    adwaita-qt6
    qt5.qtwayland
    qt6.qtwayland

    (pkgs.writeShellScriptBin "smart-launch" (builtins.readFile ../../.local/bin/smart-launch.sh))
    (pkgs.writeShellScriptBin "obsidian-launch" (builtins.readFile ../../.local/bin/obsidian-launch.sh))
    (pkgs.writeShellScriptBin "obsidian-workspace-watcher" (builtins.readFile ../../.local/bin/obsidian-workspace-watcher.sh))
    (pkgs.writeShellScriptBin "mandragora-switch" (builtins.readFile ../../.local/bin/mandragora-switch.sh))
    (pkgs.writeShellScriptBin "mandragora-commit-push" (builtins.readFile ../../.local/bin/mandragora-commit-push.sh))
    (pkgs.writeShellScriptBin "sss" (builtins.readFile ../../.local/bin/sss.sh))
    (pkgs.writeShellScriptBin "mandragora-diff" (builtins.readFile ../../.local/bin/mandragora-diff.sh))
    (pkgs.writeShellScriptBin "mandragora-diff-last" (builtins.readFile ../../.local/bin/mandragora-diff-last.sh))
    (pkgs.writeShellScriptBin "rofi-ide-picker" (builtins.readFile ../../.local/bin/rofi-ide-picker.sh))
    (pkgs.writeShellScriptBin "rofi-tool-picker" (builtins.readFile ../../.local/bin/rofi-tool-picker.sh))
    (pkgs.writeShellScriptBin "rofi-db-picker" (builtins.readFile ../../.local/bin/rofi-db-picker.sh))
    (pkgs.writeShellScriptBin "cycle-audio-output" (builtins.readFile ../../.local/bin/cycle-audio-output.sh))
    (pkgs.writeShellScriptBin "window-to-corner" (builtins.readFile ../../.local/bin/window-to-corner.sh))
    (pkgs.writeShellScriptBin "gap-adjust" (builtins.readFile ../../.local/bin/gap-adjust.sh))
    (pkgs.writeShellScriptBin "blur-adjust" (builtins.readFile ../../.local/bin/blur-adjust.sh))
    (pkgs.writeShellScriptBin "opacity-adjust" (builtins.readFile ../../.local/bin/opacity-adjust.sh))
    (pkgs.writeShellScriptBin "rofi-wallpaper-picker" (builtins.readFile ../../.local/bin/rofi-wallpaper-picker.sh))
    (pkgs.writeShellScriptBin "rofi-run-or-term" (builtins.readFile ../../.local/bin/rofi-run-or-term.sh))
    (pkgs.writeShellScriptBin "powermenu-toggle" (builtins.readFile ../../.local/bin/powermenu-toggle.sh))
    (pkgs.writeShellScriptBin "powermenu-close" (builtins.readFile ../../.local/bin/powermenu-close.sh))
    (pkgs.writeShellScriptBin "screencap" (builtins.readFile ../../.local/bin/screencap.sh))
    (pkgs.writeShellScriptBin "capture" (builtins.readFile ../../.local/bin/capture.sh))
    (pkgs.writeShellScriptBin "compv" (builtins.readFile ../../.local/bin/compv.sh))
    (pkgs.writeShellScriptBin "ic" (builtins.readFile ../../.local/bin/ic.sh))
    (pkgs.writeShellScriptBin "setbg" (builtins.readFile ../../.local/bin/setbg.sh))
    (pkgs.writeShellScriptBin "clean" (builtins.readFile ../../.local/bin/clean.sh))
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
    (pkgs.writeShellScriptBin "pop" (builtins.readFile ../../.local/bin/pop.sh))
    (pkgs.writeShellScriptBin "hid-wrapper" ''exec ${hidWrapperEnv}/bin/python3 ${../../.local/bin/hid-wrapper.py} "$@"'')
    (pkgs.writeShellScriptBin "light" ''exec ${lightEnv}/bin/python3 ${../../.local/bin/light.py} "$@"'')
    yad
    (pkgs.writeShellScriptBin "screenshot-window" (builtins.readFile ../../.local/bin/screenshot-window.sh))

    (pkgs.writeShellScriptBin "ait" (builtins.readFile ../../.local/bin/ait.sh))
    (pkgs.writeShellScriptBin "am" (builtins.readFile ../../.local/bin/am.sh))
    (pkgs.writeShellScriptBin "bonsai" (builtins.readFile ../../.local/bin/bonsai.sh))
    (pkgs.writeShellScriptBin "eit" (builtins.readFile ../../.local/bin/eit.sh))
    (pkgs.writeShellScriptBin "filedropper" (builtins.readFile ../../.local/bin/filedropper.sh))
    (pkgs.writeShellScriptBin "imap-notify" (builtins.readFile ../../.local/bin/imap-notify.sh))
    (pkgs.writeShellScriptBin "lf-ueberzug" (builtins.readFile ../../.local/bin/lf-ueberzug.sh))
    (pkgs.writeShellScriptBin "make-lf-aliases" (builtins.readFile ../../.local/bin/make-lf-aliases.sh))
    (pkgs.writeShellScriptBin "mbsync-notify" (builtins.readFile ../../.local/bin/mbsync-notify.sh))
    (pkgs.writeShellScriptBin "mvnexec" (builtins.readFile ../../.local/bin/mvnexec.sh))
    (pkgs.writeShellScriptBin "pentr" (builtins.readFile ../../.local/bin/pentr.sh))
    (pkgs.writeShellScriptBin "qit" (builtins.readFile ../../.local/bin/qit.sh))
    (pkgs.writeShellScriptBin "shfthue" (builtins.readFile ../../.local/bin/shfthue.sh))
    (pkgs.writeShellScriptBin "sit" (builtins.readFile ../../.local/bin/sit.sh))

    (pkgs.writeShellScriptBin "health-check" (builtins.readFile ../../.local/bin/health-check.sh))
    (pkgs.writeShellScriptBin "keyledsd-reload" (builtins.readFile ../../.local/bin/keyledsd-reload.sh))
    (pkgs.writeShellScriptBin "restore-theme" (builtins.readFile ../../.local/bin/restore-theme.sh))
    (pkgs.writeShellScriptBin "gemma" ''exec ${pkgs.python3}/bin/python3 ${../../.local/bin/gemma.py} "$@"'')
    (pkgs.writeShellScriptBin "wal-to-rgb" ''exec ${walToRgbEnv}/bin/python3 ${../../.local/bin/wal-to-rgb.py} "$@"'')
    (pkgs.writeShellScriptBin "wal-to-rgb-daemon" ''exec ${walToRgbEnv}/bin/python3 ${../../.local/bin/wal-to-rgb-daemon.py} "$@"'')
    (pkgs.writeShellScriptBin "strays" (
      builtins.replaceStrings ["@VAULT@" "@USER_HOME@"] ["/persistent" "/home/m"]
        (builtins.readFile ../../.local/bin/strays.sh)
    ))

    (pkgs.writeShellScriptBin "blur-strength" (builtins.readFile ../../.local/bin/blur-strength.sh))
    (pkgs.writeShellScriptBin "record-window" (builtins.readFile ../../.local/bin/record-window.sh))
    (pkgs.writeShellScriptBin "center-window" (builtins.readFile ../../.local/bin/center-window.sh))
    (pkgs.writeShellScriptBin "cycle-kbd-layouts" (builtins.readFile ../../.local/bin/cycle-kbd-layouts.sh))
    (pkgs.writeShellScriptBin "resize-window" (builtins.readFile ../../.local/bin/resize-window.sh))
    (pkgs.writeShellScriptBin "scratchpad" (builtins.readFile ../../.local/bin/scratchpad.sh))
    (pkgs.writeShellScriptBin "scratchpad-summon" (builtins.readFile ../../.local/bin/scratchpad-summon.sh))
    (pkgs.writeShellScriptBin "powermenu-toggle" (builtins.readFile ../../.local/bin/powermenu-toggle.sh))
    (pkgs.writeShellScriptBin "powermenu-close" (builtins.readFile ../../.local/bin/powermenu-close.sh))
  ];

  home.file.".local/bin/resty".source = ../../.local/bin/resty;

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    BROWSER = "firefox";
    GOPATH = "${config.home.homeDirectory}/.local/share/go";
    GOBIN = "${config.home.homeDirectory}/.local/share/go/bin";
    GTK_IM_MODULE = "cedilla";
    QT_IM_MODULE = "cedilla";
    XMODIFIERS = "@im=cedilla";
    GDK_DPI_SCALE = "1.0";
    QT_AUTO_SCREEN_SCALE_FACTOR = "1";
    QT_ENABLE_HIGHDPI_SCALING = "1";
    WALLPAPER_DIR = "${config.home.homeDirectory}/Pictures/wllpps";
    _ZO_EXCLUDE_DIRS = "/mnt/toshiba/sss:/mnt/toshiba/sss/*";
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
      window.background,
      window.background.csd,
      window.background.solid-csd,
      .background,
      window.background decoration,
      window.background headerbar,
      window.background .titlebar,
      window.background box,
      window.background grid,
      window.background stack,
      window.background scrolledwindow,
      window.background viewport,
      window.background notebook,
      window.background notebook > stack,
      window.background paned,
      window.background paned > separator {
        background-color: transparent;
        background-image: none;
      }
    '';
    gtk4.extraCss = ''
      window, window.background, window.background.csd, .background,
      headerbar, .titlebar, windowhandle,
      box, grid, stack, scrolledwindow, viewport,
      notebook, notebook > stack,
      paned, paned > separator {
        background-color: rgba(0, 0, 0, 0) !important;
        background-image: none !important;
      }
    '';
  };

  qt = {
    enable = true;
    platformTheme.name = "gtk";
    style.name = "adwaita-dark";
  };

  dconf.settings = {
    "org/nemo/window-state" = {
      start-with-menu-bar = false;
    };
  };

  programs.kitty = {
    enable = true;
    shellIntegration.mode = "no-rc no-cursor";
    font = {
      name = "Iosevka Nerd Font Mono";
      size = 11.5;
    };
    settings = {
      confirm_os_window_close = 0;
      cursor = "#cccccc";
      cursor_text_color = "#111111";
      cursor_shape = "block";
      cursor_blink_interval = "0.5";
      cursor_stop_blinking_after = "15.0";
      cursor_trail = 3;
      scrollback_lines = 2000;
      scrollback_pager = "less --chop-long-lines --RAW-CONTROL-CHARS +INPUT_LINE_NUMBER";
      wheel_scroll_multiplier = "5.0";
      url_color = "#0087BD";
      url_style = "curly";
      copy_on_select = "no";
      select_by_word_characters = ":@-./_~?&=%+#";
      mouse_hide_wait = "3.0";
      focus_follows_mouse = "no";
      repaint_delay = 16;
      input_delay = 6;
      sync_to_monitor = "no";
      enable_audio_bell = "yes";
      visual_bell_duration = "0.0";
      window_alert_on_bell = "yes";
      bell_on_tab = "yes";
      remember_window_size = "yes";
      initial_window_width = 640;
      initial_window_height = 400;
      enabled_layouts = "*";
      window_resize_step_cells = 2;
      window_resize_step_lines = 2;
      window_border_width = "1.0";
      draw_minimal_borders = "yes";
      window_margin_width = "0.0";
      window_padding_width = "0.0";
      active_border_color = "#00ff00";
      inactive_border_color = "#cccccc";
      bell_border_color = "#ff5a00";
      inactive_text_alpha = "1.0";
      hide_window_decorations = "no";
      tab_bar_edge = "bottom";
      tab_bar_style = "fade";
      tab_fade = "0.25 0.5 0.75 1";
      tab_separator = " ┇";
      active_tab_foreground = "#000";
      active_tab_background = "#eee";
      active_tab_font_style = "bold-italic";
      inactive_tab_foreground = "#444";
      inactive_tab_background = "#999";
      inactive_tab_font_style = "normal";
      foreground = "#dddddd";
      background = "#000";
      background_opacity = "0.4";
      dynamic_background_opacity = "yes";
      dim_opacity = "0.75";
      selection_foreground = "#000000";
      selection_background = "#FFFACD";
      color0 = "#000000"; color8 = "#767676";
      color1 = "#cc0403"; color9 = "#f2201f";
      color2 = "#19cb00"; color10 = "#23fd00";
      color3 = "#cecb00"; color11 = "#fffd00";
      color4 = "#0d73cc"; color12 = "#1a8fff";
      color5 = "#cb1ed1"; color13 = "#fd28ff";
      color6 = "#0dcdcd"; color14 = "#14ffff";
      color7 = "#dddddd"; color15 = "#ffffff";
      close_on_child_death = "no";
      allow_remote_control = "yes";
      listen_on = "unix:@kitty";
      clipboard_control = "write-clipboard write-primary";
      term = "xterm-kitty";
      alt_send_esc = "no";
    };
    keybindings = {
      "ctrl+backspace" = "send_text all \\x1b[127;5u";
      "ctrl+shift+c" = "copy_to_clipboard";
      "ctrl+shift+v" = "paste_from_clipboard";
      "ctrl+shift+s" = "paste_from_selection";
      "shift+insert" = "paste_from_selection";
      "ctrl+shift+up" = "scroll_line_up";
      "ctrl+shift+down" = "scroll_line_down";
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
      "ctrl+shift+`" = "move_window_to_top";
      "ctrl+shift+right" = "next_tab";
      "ctrl+shift+left" = "previous_tab";
      "ctrl+shift+t" = "new_tab";
      "ctrl+shift+q" = "no_op";
      "ctrl+shift+." = "move_tab_forward";
      "ctrl+shift+," = "move_tab_backward";
      "ctrl+shift+alt+t" = "set_tab_title";
      "ctrl+k" = "change_font_size all +1.0";
      "ctrl+j" = "change_font_size all -1.0";
      "ctrl+equal" = "change_font_size all +1.0";
      "ctrl+minus" = "change_font_size all -1.0";
      "ctrl+0" = "change_font_size all 0";
      "ctrl+shift+k" = "set_background_opacity +0.05";
      "ctrl+shift+j" = "set_background_opacity -0.05";
      "ctrl+shift+l" = "set_background_opacity 1";
      "ctrl+shift+0" = "set_background_opacity default";
      "ctrl+shift+e" = "kitten hints";
      "ctrl+shift+p>f" = "kitten hints --type path --program -";
      "ctrl+shift+p>shift+f" = "kitten hints --type path";
      "ctrl+shift+p>l" = "kitten hints --type line --program -";
      "ctrl+shift+p>w" = "kitten hints --type word --program -";
      "ctrl+shift+p>h" = "kitten hints --type hash --program -";
      "alt+1" = "send_text all \\x1b1";
      "alt+2" = "send_text all \\x1b2";
      "alt+3" = "send_text all \\x1b3";
      "alt+4" = "send_text all \\x1b4";
      "alt+5" = "send_text all \\x1b5";
      "alt+6" = "send_text all \\x1b6";
      "alt+7" = "send_text all \\x1b7";
      "alt+8" = "send_text all \\x1b8";
      "alt+9" = "send_text all \\x1b9";
      "ctrl+1" = "send_text all \\x1b[49;5u";
      "ctrl+2" = "send_text all \\x1b[50;5u";
      "ctrl+3" = "send_text all \\x1b[51;5u";
      "ctrl+4" = "send_text all \\x1b[52;5u";
      "ctrl+5" = "send_text all \\x1b[53;5u";
      "ctrl+6" = "send_text all \\x1b[54;5u";
      "ctrl+7" = "send_text all \\x1b[55;5u";
      "ctrl+8" = "send_text all \\x1b[56;5u";
      "ctrl+9" = "send_text all \\x1b[57;5u";
      "alt+space" = "send_text all \\r";
    };
    extraConfig = "include ~/.cache/matugen/colors-kitty.conf";
  };

  wayland.windowManager.hyprland = {
    enable = true;
    settings = {
      exec-once = [
        "awww-daemon"
        "restore-theme"
        "wl-paste --watch cliphist store"
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
        "kdeconnect-indicator"
      ];
    };
    extraConfig = builtins.readFile ../../.config/hypr/hyprland.conf;
  };

  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        disable_loading_bar = true;
        hide_cursor = true;
      };
      background = [{
        monitor = "";
        color = "rgb(282c34)";
        blur_passes = 2;
        blur_size = 7;
      }];
      input-field = [{
        monitor = "";
        size = "300, 50";
        position = "0, -80";
        halign = "center";
        valign = "center";
        outline_thickness = 2;
        outer_color = "rgb(61afef)";
        inner_color = "rgb(2c313c)";
        font_color = "rgb(abb2bf)";
        placeholder_text = "";
        dots_size = 0.33;
        dots_spacing = 0.15;
        dots_center = true;
      }];
      label = [{
        monitor = "";
        text = "$TIME";
        color = "rgb(abb2bf)";
        font_size = 64;
        font_family = "Iosevka Nerd Font Mono";
        position = "0, 80";
        halign = "center";
        valign = "center";
      }];
    };
  };

  services.mako = {
    enable = true;
    settings = {
      font = "Iosevka Nerd Font Mono 11";
      background-color = "#00000001";
      border-size = 1;
      border-radius = 10;
      default-timeout = 10000;
      padding = "10";
      margin = "20";
      width = 280;
      layer = "overlay";
      anchor = "bottom-right";
      max-icon-size = 48;
      max-visible = 5;
      markup = 1;
      actions = 1;
      sort = "-time";
      ignore-timeout = 0;
    };
    extraConfig = ''
      
      background-color=#00000001
      [urgency=high]
      border-color=#e06c75
      default-timeout=0
    '';
  };

  programs.firefox = {
    enable = true;
    nativeMessagingHosts = [ pkgs.tridactyl-native ];
    profiles.default = {
      isDefault = true;
      id = 0;
      path = "iwwxmo01.default";
      settings = {
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        "widget.gtk.native-context-menus" = false;
      };
      userChrome = ''
        menupopup,
        panel,
        .menupopup-arrowscrollbox {
          background-color: rgba(0, 0, 0, 0.18) !important;
          --panel-background: rgba(0, 0, 0, 0.18) !important;
          --arrowpanel-background: rgba(0, 0, 0, 0.18) !important;
          backdrop-filter: blur(20px);
        }
        menupopup menuitem,
        menupopup menu {
          background-color: transparent !important;
          color: #ffffff !important;
        }
        menupopup menuitem[_moz-menuactive="true"],
        menupopup menu[_moz-menuactive="true"] {
          background-color: rgba(255, 255, 255, 0.15) !important;
        }
        menupopup menuseparator {
          border-color: rgba(255, 255, 255, 0.15) !important;
        }
        #PopupAutoComplete,
        #PopupAutoComplete .autocomplete-richlistbox,
        #PopupAutoCompleteRichResult,
        #PopupAutoCompleteRichResult .autocomplete-richlistbox,
        #PopupSearchAutoComplete,
        #PopupSearchAutoComplete .autocomplete-richlistbox {
          background-color: rgba(0, 0, 0, 0.50) !important;
          --panel-background: rgba(0, 0, 0, 0.50) !important;
          --autocomplete-popup-background: rgba(0, 0, 0, 0.50) !important;
          --urlbarView-background: rgba(0, 0, 0, 0.50) !important;
        }
      '';
    };
    profiles.chess = {
      id = 2;
      name = "chess";
      settings = {
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        "browser.tabs.inTitlebar" = 0;
        "browser.uidensity" = 1;
        "widget.wayland.vsync.enabled" = false;
        "gfx.webrender.compositor" = false;
      };
      userChrome = ''
        #TabsToolbar { visibility: collapse !important; }
        #nav-bar { visibility: collapse !important; }
        #sidebar-box { display: none !important; }
        #titlebar { display: none !important; }
      '';
    };
    profiles.whatsapp = {
      id = 1;
      name = "whatsapp";
      settings = {
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        "browser.tabs.inTitlebar" = 0;
        "browser.uidensity" = 1;
        "widget.wayland.vsync.enabled" = false;
        "gfx.webrender.compositor" = false;
      };
      userChrome = ''
        #TabsToolbar { visibility: collapse !important; }
        #nav-bar { visibility: collapse !important; }
        #sidebar-box { display: none !important; }
        #titlebar { display: none !important; }
      '';
    };
  };

  programs.home-manager.enable = true;
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.git = {
    enable = true;
    signing.format = null;
    settings = {
      user.name = "mvrozanti";
      user.email = "mvrozanti@hotmail.com";
      push.autoSetupRemote = true;
      safe.directory = [
        "/mnt/ventoy/docs/mandragora-nixos"
        "/persistent/mandragora"
      ];
    };
  };

  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
  };

  programs.go = {
    enable = true;
    goPath = ".local/share/go";
    goBin = ".local/share/go/bin";
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
  home.file.".config/matugen" = {
    source = ../../.config/matugen;
    recursive = true;
  };
  home.file.".local/share/TelegramDesktop/matugen.tdesktop-palette".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.cache/matugen/telegram.tdesktop-palette";

  home.activation.seedKeyledsd = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -e "$HOME/.config/keyledsd.conf" ]; then
      install -Dm644 ${../../.config/keyledsd/keyledsd.conf} "$HOME/.config/keyledsd.conf"
    fi
  '';

  home.activation.seedObsStudio = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    OBS_PROFILE_DIR="$HOME/.config/obs-studio/basic/profiles/Untitled"
    if [ ! -e "$OBS_PROFILE_DIR/basic.ini" ]; then
      mkdir -p "$OBS_PROFILE_DIR"
      cat <<EOF > "$OBS_PROFILE_DIR/basic.ini"
[General]
Name=Untitled

[SimpleOutput]
FilePath=$HOME/Videos

[AdvOut]
RecFilePath=$HOME/Videos
EOF
    fi
  '';

  home.file.".config/nsxiv" = {
    source = ../../.config/nsxiv;
    recursive = true;
  };
  home.file.".config/cava/config".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.cache/matugen/cava";
  home.file.".config/khal" = {
    source = ../../.config/khal;
    recursive = true;
  };
  home.file.".config/crush/crush.json".source = ../../.config/crush/crush.json;
  home.file.".config/eww" = {
    source = ../../.config/eww;
    recursive = true;
  };
  home.file.".config/flameshot" = {
    source = ../../.config/flameshot;
    recursive = true;
  };
  home.file.".config/waybar/scripts/mpd-status.sh" = {
    source = ../../snippets/waybar-mpd.sh;
    executable = true;
  };
  home.file.".config/waybar/scripts/volume-ramp.sh" = {
    source = ../../snippets/waybar-volume-ramp.sh;
    executable = true;
  };
  home.file.".config/waybar/scripts/weather.sh" = {
    source = ../../snippets/waybar-weather.sh;
    executable = true;
  };
  home.file.".config/waybar/scripts/bluetooth.sh" = {
    source = ../../snippets/waybar-bluetooth.sh;
    executable = true;
  };
  home.file.".local/share/applications/chess-com.desktop".text = ''
[Desktop Entry]
Name=Chess.com
Exec=env MOZ_ENABLE_WAYLAND=0 MOZ_APP_REMOTINGNAME=chess-com firefox -P chess --new-instance --url https://www.chess.com
Icon=${pkgs.gnome-chess}/share/icons/hicolor/scalable/apps/org.gnome.Chess.svg
Type=Application
Categories=Game;BoardGame;
StartupWMClass=chess-com
'';
  home.file.".local/share/applications/whatsapp-web.desktop".text = ''
[Desktop Entry]
Name=WhatsApp
Exec=env MOZ_ENABLE_WAYLAND=0 MOZ_APP_REMOTINGNAME=whatsapp-web firefox -P whatsapp --new-instance --url https://web.whatsapp.com
Icon=${pkgs.zapzap}/share/icons/hicolor/scalable/apps/com.rtosta.zapzap.svg
Type=Application
Categories=Network;InstantMessaging;
StartupWMClass=whatsapp-web
'';
  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "/etc/nixos/mandragora/.claude/settings.json";
  home.file.".claude/settings.local.json".source =
    config.lib.file.mkOutOfStoreSymlink "/etc/nixos/mandragora/.claude/settings.local.json";

  home.file.".gemini/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "/etc/nixos/mandragora/.gemini/settings.json";
}
