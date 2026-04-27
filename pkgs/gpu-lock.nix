{ pkgs }:

let
  src = ../.local/share/gpu-lock;
in
pkgs.writeShellApplication {
  name = "gpu-lock";
  runtimeInputs = [ pkgs.python3 ];
  text = ''
    export PYTHONPATH=${src}''${PYTHONPATH:+:$PYTHONPATH}
    exec ${pkgs.python3}/bin/python3 ${src}/gpu_lock_cli.py "$@"
  '';
}
