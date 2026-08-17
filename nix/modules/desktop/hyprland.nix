{ lib, pkgs, ... }:
let
  xdphReloadGuard = pkgs.writeShellApplication {
    name = "xdph-reload-guard";
    runtimeInputs = [
      pkgs.socat
      pkgs.systemd
    ];
    text = builtins.readFile ../../../.local/bin/xdph-reload-guard.sh;
  };
  awwwRestore = pkgs.writeShellApplication {
    name = "awww-restore";
    runtimeInputs = [
      pkgs.awww
      pkgs.coreutils
    ];
    text = builtins.readFile ../../../.local/bin/awww-restore.sh;
  };
  sessionAutostarts = {
    awww-daemon = "${pkgs.awww}/bin/awww-daemon";
    cliphist-store = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store";
    polkit-gnome-agent = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
    kdeconnect-indicator = "${pkgs.kdePackages.kdeconnect-kde}/bin/kdeconnect-indicator";
    blueman-applet = "${pkgs.blueman}/bin/blueman-applet";
  };
in
{
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  environment.systemPackages = [ pkgs.wshowkeys ];

  security.wrappers.wshowkeys = {
    source = "${pkgs.wshowkeys}/bin/wshowkeys";
    owner = "root";
    group = "root";
    setuid = true;
  };

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    LIBVA_DRIVER_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    XDG_SESSION_TYPE = "wayland";
  };

  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
    ];
    config.common = {
      default = [
        "hyprland"
        "gtk"
      ];
      "org.freedesktop.impl.portal.Screenshot" = [ "hyprland" ];
      "org.freedesktop.impl.portal.ScreenCast" = [ "hyprland" ];
    };
  };

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    wireplumber = {
      enable = true;
      configPackages = [
        (pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/99-hdmi-default.conf" (
          builtins.readFile ../../../.config/wireplumber/hdmi-default.conf
        ))
      ];
    };
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  fonts.packages = with pkgs; [
    ubuntu-classic
    icomoon-feather
    nerd-fonts.terminess-ttf
    nerd-fonts.droid-sans-mono
    weather-icons
    material-icons
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

  systemd.user.paths.wayland-socket-watch = {
    description = "Watch wayland-1 socket for compositor restart";
    wantedBy = [ "default.target" ];
    pathConfig = {
      PathModified = "%t/wayland-1";
      Unit = "wayland-socket-restart-deps.service";
    };
  };

  systemd.user.services =
    lib.mapAttrs (name: exec: {
      description = "Hyprland session autostart: ${name}";
      wantedBy = [ "hyprland-session.target" ];
      partOf = [ "hyprland-session.target" ];
      after = [ "hyprland-session.target" ];
      unitConfig = {
        StartLimitIntervalSec = 60;
        StartLimitBurst = 10;
      };
      serviceConfig = {
        ExecStart = exec;
        Restart = "on-failure";
        RestartSec = "2s";
      };
    }) sessionAutostarts
    // {
      wayland-socket-restart-deps = {
        description = "Restart user services holding stale wayland refs after compositor restart";
        serviceConfig = {
          Type = "oneshot";
          ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
          ExecStart = [
            "${pkgs.systemd}/bin/systemctl --user try-restart kdeconnectd.service xdg-desktop-portal.service xdg-desktop-portal-hyprland.service monitor-audio-follow.service"
            "${pkgs.systemd}/bin/systemctl --user restart ${
              lib.concatStringsSep " " (map (n: "${n}.service") (builtins.attrNames sessionAutostarts))
            }"
            "${pkgs.systemd}/bin/systemctl --user restart awww-restore.service"
          ];
        };
      };

      awww-restore = {
        description = "Re-apply the last wallpaper image after awww-daemon starts";
        wantedBy = [ "hyprland-session.target" ];
        after = [
          "hyprland-session.target"
          "awww-daemon.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${awwwRestore}/bin/awww-restore";
        };
      };

      xdph-reload-guard = {
        description = "Restart xdg-desktop-portal on Hyprland config reload to keep screencast alive";
        wantedBy = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${xdphReloadGuard}/bin/xdph-reload-guard";
          Restart = "on-failure";
          RestartSec = "3s";
        };
      };
    };
}
