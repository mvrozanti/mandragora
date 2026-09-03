{ pkgs }:

let
  vtagSrc = pkgs.fetchFromGitHub {
    owner = "mvrozanti";
    repo = "vtag";
    rev = "f01b62409fe0ce18b7b357806f67e06cc38a18cb";
    sha256 = "sha256-ZtYSaO7JPy8hnRN5kpbKERZbng5qaWvzH8DIqEv10wc=";
  };
  gpuLockRoot = ../../.local/share/gpu-lock;
  botPython = import ./bot-python.nix { inherit pkgs; };

  vtag = pkgs.writeShellApplication {
    name = "vtag";
    runtimeInputs = [
      botPython
      pkgs.exiftool
    ];
    text = ''
      export PYTHONPATH=${gpuLockRoot}:${vtagSrc}''${PYTHONPATH:+:$PYTHONPATH}
      exec ${botPython}/bin/python3 ${vtagSrc}/cli.py "$@"
    '';
  };

  vfind = pkgs.writeShellApplication {
    name = "vfind";
    runtimeInputs = [
      botPython
      pkgs.exiftool
    ];
    text = ''
      exec ${botPython}/bin/python3 ${vtagSrc}/find.py "$@"
    '';
  };

  vtag-server = pkgs.writeShellApplication {
    name = "vtag-server";
    runtimeInputs = [
      botPython
      pkgs.exiftool
    ];
    text = ''
      export PYTHONPATH=${gpuLockRoot}:${vtagSrc}''${PYTHONPATH:+:$PYTHONPATH}
      exec ${botPython}/bin/python3 ${vtagSrc}/server.py "$@"
    '';
  };
in
{
  inherit vtag vfind vtag-server;
}
