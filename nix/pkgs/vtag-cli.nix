{ pkgs }:

let
  vtagSrc = pkgs.fetchFromGitHub {
    owner = "mvrozanti";
    repo = "vtag";
    rev = "e458fe9ec3ba902c3d8492851b38cbec60376b7f";
    sha256 = "sha256-i72bGVVVw8DZYcURuOImSbWtcJp8PJYljFhNdpq4208=";
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
