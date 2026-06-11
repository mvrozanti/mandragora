{ pkgs }:

let
  src = ../../.local/share/emotion-web;
in
pkgs.writeShellApplication {
  name = "emotion-web";
  runtimeInputs = [ pkgs.python3 pkgs.bashInteractive pkgs.gnused pkgs.gnugrep ];
  text = ''
    export EMOTION_WEB_STATIC_DIR="${src}/static"
    exec ${pkgs.python3}/bin/python3 ${src}/server.py "$@"
  '';
}
