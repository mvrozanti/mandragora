{ pkgs }:

pkgs.writeShellApplication {
  name = "mandragora-notify";
  bashOptions = [
    "nounset"
    "pipefail"
  ];
  runtimeInputs = [
    pkgs.coreutils
    pkgs.curl
    pkgs.jq
    pkgs.libnotify
    pkgs.util-linux
  ];
  text = builtins.readFile ../../.local/bin/mandragora-notify.sh;
}
