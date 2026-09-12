{ pkgs }:

let
  src = ../../.local/share/voice-alter-core;
  py = pkgs.python3.withPackages (p: [
    p.fastapi
    p.uvicorn
    p.websockets
  ]);
in
pkgs.writeShellApplication {
  name = "voice-alter-core";
  runtimeInputs = [
    py
    pkgs.bashInteractive
  ];
  text = ''
    exec ${py}/bin/python3 ${src}/server.py "$@"
  '';
}
