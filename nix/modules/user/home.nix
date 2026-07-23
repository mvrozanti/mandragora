{ pkgs, ... }:

let
  pyDictEnv = pkgs.python3.withPackages (
    ps: with ps; [
      requests
      beautifulsoup4
      lxml
    ]
  );
  pySinonEnv = pkgs.python3.withPackages (
    ps: with ps; [
      requests
      beautifulsoup4
      lxml
      unidecode
    ]
  );
  hidWrapperEnv = pkgs.python3.withPackages (ps: [
    ps.colour
    ps.openrgb-python
    (pkgs.python3.pkgs.toPythonModule pkgs.rivalcfg)
  ]);
  lightEnv = pkgs.python3.withPackages (
    ps: with ps; [
      requests
      numpy
    ]
  );
  walToRgbEnv = pkgs.python3.withPackages (ps: with ps; [ openrgb-python ]);
in
{
  imports = [
    ../shared/home-cli.nix
    ./zsh.nix
    ./tmux.nix
    ./yazi.nix
    ./services.nix
    ./bots.nix
    ./waybar.nix
    ./rss-menu.nix
    ./ea-reaper.nix
    ./security-menu.nix
    ./weather-menu.nix
    ./monitor-menu.nix
    ./network-menu.nix
    ./monitor-audio.nix
    ./minecraft.nix
    ./skills.nix
    ./axon.nix
    ./nb-vault-sync.nix
    ./path-filter.nix
    ./autoclaude.nix
    ./session.nix
    ./theme.nix
    ./terminal.nix
    ./desktop-shell.nix
    ./file-links.nix
  ];

  home.packages = with pkgs; [
    xdg-desktop-portal-gtk
    (callPackage ../../pkgs/hypr-kdeconnect-portal { })
    bubblewrap
    ripgrep
    droidcam
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
    msmtp
    aerc
    notmuch
    transmission_4
    tremc
    rustmission
    libnotify

    mpv
    (pkgs.nsxiv.overrideAttrs (oldAttrs: {
      patches = (oldAttrs.patches or [ ]) ++ [ ../../pkgs/nsxiv/commands.patch ];
      postPatch = (oldAttrs.postPatch or "") + "cp ${../../pkgs/nsxiv/config.h} config.def.h";
    }))
    zathura
    calibre
    imagemagick
    ffmpeg
    ffmpegthumbnailer
    psmisc
    awww

    gh-dash
    neovim
    (python3.withPackages (
      ps: with ps; [
        pynvim
        grip
        psutil
      ]
    ))
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
    typst
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
    (pkgs.writeShellScriptBin "translate" "exec ${pkgs.translate-shell}/bin/trans -b \"$@\"")
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
    lutris
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
    xdot
    gephi
    mkvtoolnix
    jiq

    telegram-desktop
    (pkgs.symlinkJoin {
      name = "vesktop";
      paths = [ pkgs.vesktop ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/vesktop \
          --add-flags "--ozone-platform-hint=auto" \
          --add-flags "--enable-features=WaylandWindowDecorations,WebRTCPipeWireCapturer" \
          --add-flags "--enable-wayland-ime"
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
    qgnomeplatform
    qgnomeplatform-qt6
    qt5.qtwayland
    qt6.qtwayland

    (pkgs.writeShellScriptBin "smart-launch" (builtins.readFile ../../../.local/bin/smart-launch.sh))
    (pkgs.writeShellScriptBin "obsidian-launch" (
      builtins.readFile ../../../.local/bin/obsidian-launch.sh
    ))
    (pkgs.writeShellScriptBin "obsidian-workspace-watcher" (
      builtins.readFile ../../../.local/bin/obsidian-workspace-watcher.sh
    ))
    (pkgs.writeShellScriptBin "mandragora-switch" (
      builtins.readFile ../../../.local/bin/mandragora-switch.sh
    ))
    (pkgs.writeShellScriptBin "spawn-claude-tmux" (
      builtins.readFile ../../../.local/bin/spawn-claude-tmux.sh
    ))
    (pkgs.writeShellScriptBin "safe-claude" (builtins.readFile ../../../.local/bin/safe-claude.sh))
    (pkgs.writeShellScriptBin "claude-deepseek" (
      builtins.readFile ../../../.local/bin/claude-deepseek.sh
    ))
    (pkgs.writeShellScriptBin "mandragora-commit-push" (
      builtins.readFile ../../../.local/bin/mandragora-commit-push.sh
    ))
    (pkgs.writeShellScriptBin "sss" (builtins.readFile ../../../.local/bin/sss.sh))
    (pkgs.writeShellScriptBin "mandragora-diff" (
      builtins.readFile ../../../.local/bin/mandragora-diff.sh
    ))
    (pkgs.writeShellScriptBin "mandragora-diff-last" (
      builtins.readFile ../../../.local/bin/mandragora-diff-last.sh
    ))
    (pkgs.writeShellScriptBin "circleci-fetch" (
      builtins.readFile ../../../.local/bin/circleci-fetch.sh
    ))
    (pkgs.writeShellScriptBin "mandragora-winvm" (
      builtins.readFile ../../../.local/bin/mandragora-winvm.sh
    ))
    (pkgs.writeShellScriptBin "rofi-ide-picker" (
      builtins.readFile ../../../.local/bin/rofi-ide-picker.sh
    ))
    (pkgs.writeShellScriptBin "rofi-tool-picker" (
      builtins.readFile ../../../.local/bin/rofi-tool-picker.sh
    ))
    (pkgs.writeShellScriptBin "rofi-run" (builtins.readFile ../../../.local/bin/rofi-run.sh))
    (pkgs.writeShellScriptBin "rofi-db-picker" (
      builtins.readFile ../../../.local/bin/rofi-db-picker.sh
    ))
    (pkgs.writeShellScriptBin "cycle-audio-output" (
      builtins.readFile ../../../.local/bin/cycle-audio-output.sh
    ))
    (pkgs.writeShellScriptBin "zathura-cycle" (builtins.readFile ../../../.local/bin/zathura-cycle.sh))
    (pkgs.writeShellScriptBin "window-to-corner" (
      builtins.readFile ../../../.local/bin/window-to-corner.sh
    ))
    (pkgs.writeShellScriptBin "gap-adjust" (builtins.readFile ../../../.local/bin/gap-adjust.sh))
    (pkgs.writeShellScriptBin "blur-adjust" (builtins.readFile ../../../.local/bin/blur-adjust.sh))
    (pkgs.writeShellScriptBin "opacity-adjust" (
      builtins.readFile ../../../.local/bin/opacity-adjust.sh
    ))
    (pkgs.writeShellScriptBin "rofi-wallpaper-picker" (
      builtins.readFile ../../../.local/bin/rofi-wallpaper-picker.sh
    ))
    (pkgs.writeShellScriptBin "clipboard-menu" (
      builtins.readFile ../../../.local/bin/clipboard-menu.sh
    ))
    (pkgs.writeShellScriptBin "rofi-power-menu" (
      builtins.readFile ../../../.local/bin/rofi-power-menu.sh
    ))
    (pkgs.writeShellScriptBin "rofi-capture-menu" (
      builtins.readFile ../../../.local/bin/rofi-capture-menu.sh
    ))
    (pkgs.writeShellScriptBin "screencap" (builtins.readFile ../../../.local/bin/screencap.sh))
    (pkgs.writeShellScriptBin "screenkey-toggle" (
      builtins.readFile ../../../.local/bin/screenkey-toggle.sh
    ))
    (pkgs.writeShellScriptBin "capture" (builtins.readFile ../../../.local/bin/capture.sh))
    (pkgs.writeShellScriptBin "compv" (builtins.readFile ../../../.local/bin/compv.sh))
    (pkgs.writeShellScriptBin "ic" (builtins.readFile ../../../.local/bin/ic.sh))
    (pkgs.writeShellScriptBin "setbg" (builtins.readFile ../../../.local/bin/setbg.sh))
    (pkgs.writeShellScriptBin "clean" (builtins.readFile ../../../.local/bin/clean.sh))
    (pkgs.writeShellScriptBin "gmp" (builtins.readFile ../../../.local/bin/gmp.sh))
    (pkgs.writeShellScriptBin "mkv2gif" (builtins.readFile ../../../.local/bin/mkv2gif.sh))
    (pkgs.writeShellScriptBin "mov2gif" (builtins.readFile ../../../.local/bin/mov2gif.sh))
    (pkgs.writeShellScriptBin "mp42gif" (builtins.readFile ../../../.local/bin/mp42gif.sh))
    (pkgs.writeShellScriptBin "roman" (builtins.readFile ../../../.local/bin/roman.sh))
    (pkgs.writeShellScriptBin "lipsum" (builtins.readFile ../../../.local/bin/lipsum.sh))
    (pkgs.writeShellScriptBin "wiki" (builtins.readFile ../../../.local/bin/wiki.sh))
    (pkgs.writeShellScriptBin "after" (builtins.readFile ../../../.local/bin/after.sh))
    (pkgs.writeShellScriptBin "are-processes-related" (
      builtins.readFile ../../../.local/bin/are-processes-related.sh
    ))
    (pkgs.writeShellScriptBin "ea-destage-fix" (
      builtins.readFile ../../../.local/bin/ea-destage-fix.sh
    ))
    (pkgs.writeShellScriptBin "explode_tmux" (builtins.readFile ../../../.local/bin/explode_tmux.sh))
    (pkgs.writeShellScriptBin "implode_tmux" (builtins.readFile ../../../.local/bin/implode_tmux.sh))
    (pkgs.writeShellScriptBin "superscript" ''exec ${pkgs.python3}/bin/python3 ${../../../.local/bin/superscript.py} "$@"'')
    (pkgs.writeShellScriptBin "vaporscript" ''exec ${pkgs.python3}/bin/python3 ${../../../.local/bin/vaporscript.py} "$@"'')
    (pkgs.writeShellScriptBin "cursivescript" ''exec ${pkgs.python3}/bin/python3 ${../../../.local/bin/cursivescript.py} "$@"'')
    (pkgs.writeShellScriptBin "dict" ''exec ${pyDictEnv}/bin/python3 ${../../../.local/bin/dict.py} "$@"'')
    (pkgs.writeShellScriptBin "sinon" ''exec ${pySinonEnv}/bin/python3 ${../../../.local/bin/sinon.py} "$@"'')
    (pkgs.writeShellScriptBin "biggest-pane" (builtins.readFile ../../../.local/bin/biggest-pane.sh))
    (pkgs.writeShellScriptBin "desktop-toggle" (
      builtins.readFile ../../../.local/bin/desktop-toggle.sh
    ))
    (pkgs.writeShellScriptBin "pop" (builtins.readFile ../../../.local/bin/pop.sh))
    (pkgs.writeShellScriptBin "hid-wrapper" ''exec ${hidWrapperEnv}/bin/python3 ${../../../.local/bin/hid-wrapper.py} "$@"'')
    (pkgs.writeShellScriptBin "light" ''exec ${lightEnv}/bin/python3 ${../../../.local/bin/light.py} "$@"'')
    yad
    nwg-displays
    (pkgs.writeShellScriptBin "ragnarok" (builtins.readFile ../../../.local/bin/ragnarok.sh))
    (pkgs.writeShellScriptBin "screenshot-window" (
      builtins.readFile ../../../.local/bin/screenshot-window.sh
    ))

    (pkgs.writeShellScriptBin "ait" (builtins.readFile ../../../.local/bin/ait.sh))
    (pkgs.writeShellScriptBin "bonsai" (builtins.readFile ../../../.local/bin/bonsai.sh))
    (pkgs.writeShellScriptBin "eit" (builtins.readFile ../../../.local/bin/eit.sh))
    (pkgs.writeShellScriptBin "filedropper" (builtins.readFile ../../../.local/bin/filedropper.sh))
    (pkgs.writeShellScriptBin "mvnexec" (builtins.readFile ../../../.local/bin/mvnexec.sh))
    (pkgs.writeShellScriptBin "pentr" (builtins.readFile ../../../.local/bin/pentr.sh))
    (pkgs.writeShellScriptBin "qit" (builtins.readFile ../../../.local/bin/qit.sh))
    (pkgs.writeShellScriptBin "shfthue" (builtins.readFile ../../../.local/bin/shfthue.sh))
    (pkgs.writeShellScriptBin "sit" (builtins.readFile ../../../.local/bin/sit.sh))

    (pkgs.writeShellScriptBin "health-check" (builtins.readFile ../../../.local/bin/health-check.sh))
    (pkgs.writeShellScriptBin "keyledsd-reload" (
      builtins.readFile ../../../.local/bin/keyledsd-reload.sh
    ))
    (pkgs.writeShellScriptBin "restore-theme" (builtins.readFile ../../../.local/bin/restore-theme.sh))
    (pkgs.writeShellScriptBin "gemma" ''exec ${pkgs.python3}/bin/python3 ${../../../.local/bin/gemma.py} "$@"'')
    (pkgs.writeShellScriptBin "wal-to-rgb" ''exec ${walToRgbEnv}/bin/python3 ${../../../.local/bin/wal-to-rgb.py} "$@"'')
    (pkgs.writeShellScriptBin "wal-to-rgb-daemon" ''exec ${walToRgbEnv}/bin/python3 ${../../../.local/bin/wal-to-rgb-daemon.py} "$@"'')
    (pkgs.writeShellScriptBin "strays" (
      builtins.replaceStrings [ "@VAULT@" "@USER_HOME@" ] [ "/persistent" "/home/m" ] (
        builtins.readFile ../../../.local/bin/strays.sh
      )
    ))

    (pkgs.writeShellScriptBin "blur-strength" (builtins.readFile ../../../.local/bin/blur-strength.sh))
    (pkgs.writeShellScriptBin "record-window" (builtins.readFile ../../../.local/bin/record-window.sh))
    (pkgs.writeShellScriptBin "center-window" (builtins.readFile ../../../.local/bin/center-window.sh))
    (pkgs.writeShellScriptBin "cycle-kbd-layouts" (
      builtins.readFile ../../../.local/bin/cycle-kbd-layouts.sh
    ))
    (pkgs.writeShellScriptBin "resize-window" (builtins.readFile ../../../.local/bin/resize-window.sh))
    (pkgs.writeShellScriptBin "scratchpad" (builtins.readFile ../../../.local/bin/scratchpad.sh))
    (pkgs.writeShellScriptBin "scratchpad-summon" (
      builtins.readFile ../../../.local/bin/scratchpad-summon.sh
    ))
    (pkgs.writeShellScriptBin "imagine" (builtins.readFile ../../../.local/bin/imagine.sh))
    gpick
    hyprpicker
  ];

  home.file.".local/bin/resty".source = ../../../.local/bin/resty;

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
      userChrome = builtins.readFile ../../snippets/firefox-userchrome-default.css;
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
      userChrome = builtins.readFile ../../snippets/firefox-userchrome-kiosk.css;
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
      userChrome = builtins.readFile ../../snippets/firefox-userchrome-kiosk.css;
    };
  };
}
