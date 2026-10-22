{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  rofi,
  libnotify,
  xdg-utils,
  procps,
  systemd,
  wl-clipboard,
  mutt-oauth2,
}:
stdenvNoCC.mkDerivation {
  pname = "mail-menu";
  version = "1";
  src = ../../snippets/mail-menu.py;
  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ python3 ];
  installPhase = ''
    install -Dm755 $src $out/bin/mail-menu
    patchShebangs $out/bin
    wrapProgram $out/bin/mail-menu \
      --set MAIL_MENU_BIN $out/bin/mail-menu \
      --prefix PATH : ${
        lib.makeBinPath [
          rofi
          libnotify
          xdg-utils
          procps
          systemd
          wl-clipboard
          mutt-oauth2
        ]
      }
  '';
}
