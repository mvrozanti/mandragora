{ pkgs }:

let
  vtagSrc = pkgs.fetchFromGitHub {
    owner = "mvrozanti";
    repo = "vtag";
    rev = "6d36ef3b5e89d5c850d45488661cce52febc8f2d";
    sha256 = "sha256-LFWbN8B94skIM+ZDkczUbPUC6aWANAEf94BUGBrpFYs=";
  };
  gpuLockRoot = "/etc/nixos/mandragora/.local/share/gpu-lock";
  botPython = import ./bot-python.nix { inherit pkgs; };

  vtag = pkgs.writeShellApplication {
    name = "vtag";
    runtimeInputs = [ botPython pkgs.exiftool ];
    text = ''
      export PYTHONPATH=${gpuLockRoot}:${vtagSrc}''${PYTHONPATH:+:$PYTHONPATH}
      exec ${botPython}/bin/python3 ${vtagSrc}/cli.py "$@"
    '';
  };

  vfind = pkgs.writeShellApplication {
    name = "vfind";
    runtimeInputs = [ botPython pkgs.exiftool ];
    text = ''
      exec ${botPython}/bin/python3 ${vtagSrc}/find.py "$@"
    '';
  };

  vtag-server = pkgs.writeShellApplication {
    name = "vtag-server";
    runtimeInputs = [ botPython pkgs.exiftool ];
    text = ''
      export PYTHONPATH=${gpuLockRoot}:${vtagSrc}''${PYTHONPATH:+:$PYTHONPATH}
      exec ${botPython}/bin/python3 ${vtagSrc}/server.py "$@"
    '';
  };
in
{
  inherit vtag vfind vtag-server;
}
