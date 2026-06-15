{ pkgs }:

let
  vtagSrc = pkgs.fetchFromGitHub {
    owner = "mvrozanti";
    repo = "vtag";
    rev = "fd1a161ad472748d2bfa52f33e0a98501a1b0a99";
    sha256 = "sha256-DRtTcGpb52GsAtRmcs5Bm/WJ0jelOPZnIJmZn0F92Iw=";
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
