{ pkgs, ... }:

let
  headlessChrome = pkgs.writeShellScript "headless-chrome" (
    builtins.replaceStrings [ "@chromium@" ] [ "${pkgs.chromium}/bin/chromium" ] (
      builtins.readFile ../../../.local/bin/headless-chrome.sh
    )
  );
in
{
  systemd.tmpfiles.rules = [
    "L+ /opt/google/chrome/chrome - - - - ${headlessChrome}"
  ];
}
