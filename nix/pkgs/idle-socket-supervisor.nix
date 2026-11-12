{ pkgs }:

pkgs.writers.writePython3Bin "idle-socket-supervisor" {
  libraries = [ ];
  doCheck = false;
} (builtins.readFile ../../.local/bin/idle-socket-supervisor.py)
