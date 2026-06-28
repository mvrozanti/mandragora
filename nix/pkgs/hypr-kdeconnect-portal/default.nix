{ lib
, stdenv
, cmake
, pkg-config
, wayland
, wayland-scanner
, libxkbcommon
, libei
, qt6
, kdePackages
}:

stdenv.mkDerivation (_finalAttrs: {
  pname = "hypr-kdeconnect-portal";
  version = "0-unstable-2026-06-19";

  src = ./source;

  nativeBuildInputs = [
    cmake
    pkg-config
    wayland-scanner
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    qt6.qtbase
    wayland
    libxkbcommon
    libei
  ];

  postPatch = ''
    substituteInPlace src/security_policy.hpp \
      --replace-fail 'QStringLiteral("/usr/libexec/kdeconnectd");' 'QStringLiteral("/usr/libexec/kdeconnectd") ||
           executablePath == QStringLiteral("${kdePackages.kdeconnect-kde}/bin/kdeconnectd") ||
           executablePath == QStringLiteral("${kdePackages.kdeconnect-kde}/bin/.kdeconnectd-wrapped");'
  '';

  doCheck = true;

  meta = {
    description = "RemoteDesktop xdg-portal backend enabling KDE Connect remote input on Hyprland/wlroots";
    longDescription = ''
      Vendored, audited build of iamnarayana/wayland-kdeconnect-fix @ ea55f66.
      Implements org.freedesktop.impl.portal.RemoteDesktop, injecting events via
      the wlr virtual-pointer and virtual-keyboard Wayland protocols. The empty
      app-id fallback additionally allowlists the exact Nix store path of this
      build's kdeconnectd; the D-Bus-name-ownership gate remains the authorization
      lock and the upstream /tmp and bare-name rejections are preserved.
    '';
    homepage = "https://github.com/iamnarayana/wayland-kdeconnect-fix";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "hypr-kdeconnect-portal";
  };
})
