{ pkgs }:

let
  vtagSrc = pkgs.fetchFromGitHub {
    owner = "mvrozanti";
    repo = "vtag";
    rev = "d86cfaeb56f76901800fdcc8ac2706a2e17a447a";
    sha256 = "02q9siv50brrz5rlnqpmd6hfbmzzdif96m0hc02bvr81lbmf6il3";
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
    runtimeInputs = [ botPython ];
    text = ''
      exec ${botPython}/bin/python3 ${vtagSrc}/find.py "$@"
    '';
  };
in
{
  inherit vtag vfind;
}
