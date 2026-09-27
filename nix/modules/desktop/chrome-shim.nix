{ pkgs, ... }:

{
  systemd.tmpfiles.rules = [
    "L+ /opt/google/chrome/chrome - - - - ${pkgs.chromium}/bin/chromium"
  ];
}
