{ pkgs }:

let
  vtagRoot = "/etc/nixos/mandragora/.local/share/vtag";
  gpuLockRoot = "/etc/nixos/mandragora/.local/share/gpu-lock";
  botPython = import ./bot-python.nix { inherit pkgs; };

  vtag = pkgs.writeShellApplication {
    name = "vtag";
    runtimeInputs = [ botPython pkgs.exiftool ];
    text = ''
      export PYTHONPATH=${gpuLockRoot}:${vtagRoot}''${PYTHONPATH:+:$PYTHONPATH}
      exec ${botPython}/bin/python3 ${vtagRoot}/cli.py "$@"
    '';
  };

  vfind = pkgs.writeShellApplication {
    name = "vfind";
    runtimeInputs = [ botPython ];
    text = ''
      exec ${botPython}/bin/python3 ${vtagRoot}/find.py "$@"
    '';
  };
in
{
  inherit vtag vfind;
}
