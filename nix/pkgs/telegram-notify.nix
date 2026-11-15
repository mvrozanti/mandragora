{ pkgs }:

pkgs.writeShellApplication {
  name = "telegram-notify";
  bashOptions = [
    "nounset"
    "pipefail"
  ];
  runtimeInputs = [
    pkgs.coreutils
    pkgs.curl
    pkgs.libnotify
    pkgs.util-linux
  ];
  text = builtins.readFile ../../.local/bin/telegram-notify.sh;
}
