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
    ueberzugpp
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
    prismlauncher

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
    vesktop
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
    (pkgs.writeShellScriptBin "rofi-run-or-term" (builtins.readFile ../../.local/bin/rofi-run-or-term.sh))
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
    (pkgs.writeShellScriptBin "theme-engine" (builtins.readFile ../../.local/bin/theme-engine.sh))
    (pkgs.writeShellScriptBin "gemma" ''exec ${pkgs.python3}/bin/python3 ${../../.local/bin/gemma.py} "$@"'')
    (pkgs.writeShellScriptBin "wal-to-rgb" ''exec ${walToRgbEnv}/bin/python3 ${../../.local/bin/wal-to-rgb.py} "$@"'')
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
      confirm_os_window_close = 0;
      cursor = "#cccccc";
      cursor_text_color = "#111111";
      cursor_shape = "block";
      cursor_blink_interval = "0.5";
      cursor_stop_blinking_after = "15.0";
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
      background_opacity = "0.88";
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
      alt_send_esc = "yes";
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
    };
  };

  wayland.windowManager.hyprland = {
    enable = true;
    settings = {
      exec-once = [
        "awww-daemon"
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

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "hyprlock";
        before_sleep_cmd = "hyprlock";
      };
      listener = [
        {
          timeout = 300;
          on-timeout = "hyprlock";
        }
        {
          timeout = 600;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
      ];
    };
  };

  services.mako = {
    enable = true;
    settings = {
      font = "Iosevka Nerd Font Mono 11";
      background-color = "#282c34";
      text-color = "#abb2bf";
      border-color = "#61afef";
      border-size = 2;
      border-radius = 8;
      default-timeout = 5000;
      padding = "8";
      margin = "8";
      width = 360;
      layer = "overlay";
    };
  };

  programs.firefox = {
    enable = true;
    nativeMessagingHosts = [ pkgs.tridactyl-native ];
    profiles.m = {
      isDefault = true;
      id = 0;
    };
    profiles.whatsapp = {
      id = 1;
      name = "whatsapp";
    };
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
  home.file.".config/sxiv" = {
    source = ../../.config/sxiv;
    recursive = true;
  };
  home.file.".config/cava" = {
    source = ../../.config/cava;
    recursive = true;
  };
  home.file.".config/khal" = {
    source = ../../.config/khal;
    recursive = true;
  };
  home.file.".config/waybar/scripts/obs-recording.sh" = {
    source = ../../snippets/waybar-obs-recording.sh;
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
  home.file.".local/share/applications/whatsapp-web.desktop".text = ''
[Desktop Entry]
Name=WhatsApp
Exec=env MOZ_APP_REMOTINGNAME=whatsapp-web firefox -P whatsapp --new-instance --url https://web.whatsapp.com
Icon=${pkgs.zapzap}/share/icons/hicolor/scalable/apps/com.rtosta.zapzap.svg
Type=Application
Categories=Network;InstantMessaging;
StartupWMClass=whatsapp-web
'';
}
