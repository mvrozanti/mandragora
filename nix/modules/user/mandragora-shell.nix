{ pkgs, inputs, ... }:

let
  astal = inputs.ags.packages.${pkgs.stdenv.hostPlatform.system};

  mandragora-shell = pkgs.stdenv.mkDerivation {
    pname = "mandragora-shell";
    version = "1.0.0";
    src = ../../../.config/ags;

    nativeBuildInputs = [
      pkgs.wrapGAppsHook3
      pkgs.gobject-introspection
      astal.default
    ];

    buildInputs = [
      astal.io
      astal.astal4
      astal.notifd
      pkgs.gjs
      pkgs.glib
      pkgs.gdk-pixbuf
      pkgs.libsoup_3
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      ags bundle app.ts $out/bin/mandragora-shell
      install -Dm644 ${../../snippets/mandragora-shell-notifications.service} \
        $out/share/dbus-1/services/org.freedesktop.Notifications.service
      runHook postInstall
    '';
  };

  shell-popup = pkgs.writeShellScriptBin "shell-popup" (
    builtins.readFile ../../../.local/bin/shell-popup.sh
  );

  shell-notif = pkgs.writeShellScriptBin "shell-notif" (
    builtins.readFile ../../../.local/bin/shell-notif.sh
  );
in
{
  home.packages = [
    mandragora-shell
    shell-popup
    shell-notif
  ];

  systemd.user.services.mandragora-shell = {
    Unit = {
      Description = "Mandragora shell popups (AGS)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${mandragora-shell}/bin/mandragora-shell";
      Restart = "always";
      RestartSec = "2";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
