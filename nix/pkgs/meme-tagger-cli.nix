{ pkgs }:

let
  memeTaggerRoot = "/etc/nixos/mandragora/.local/share/meme-tagger";
  gpuLockRoot = "/etc/nixos/mandragora/.local/share/gpu-lock";
  botPython = import ./bot-python.nix { inherit pkgs; };

  meme-tagger = pkgs.writeShellApplication {
    name = "meme-tagger";
    runtimeInputs = [ botPython pkgs.exiftool ];
    text = ''
      export PYTHONPATH=${gpuLockRoot}:${memeTaggerRoot}''${PYTHONPATH:+:$PYTHONPATH}
      exec ${botPython}/bin/python3 ${memeTaggerRoot}/cli.py "$@"
    '';
  };

  meme-find = pkgs.writeShellApplication {
    name = "meme-find";
    runtimeInputs = [ botPython ];
    text = ''
      exec ${botPython}/bin/python3 ${memeTaggerRoot}/find.py "$@"
    '';
  };
in
{
  inherit meme-tagger meme-find;
}
