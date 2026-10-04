{ pkgs }:

let
  upstreamSrc = pkgs.fetchFromGitHub {
    owner = "mvrozanti";
    repo = "vtag";
    rev = "23baf208e9b6721c9c9548f0a61aa4d970f434fd";
    sha256 = "sha256-PxAZNeevS+hqm1vbJ9qKxlXSGaWfBaGOpz2p9T856Wo=";
  };

  memeSrc = pkgs.runCommand "meme-src" { } ''
    cp -r ${upstreamSrc} $out
    chmod -R u+w $out
    substituteInPlace $out/webui/static/index.html \
      --replace-fail '<title>vtag · mvr.ac</title>' '<title>meme · mvr.ac</title>' \
      --replace-fail '<span class="brand">vtag</span>' '<span class="brand">meme</span>'
    substituteInPlace $out/cli.py \
      --replace-fail 'prog="vtag"' 'prog="meme"' \
      --replace-fail '"""vtag CLI:' '"""meme CLI:' \
      --replace-fail 'cmd = ["vtag", "tag"]' 'cmd = ["meme", "tag"]'
  '';
  gpuLockRoot = ../../.local/share/gpu-lock;
  botPython = import ./bot-python.nix { inherit pkgs; };

  meme = pkgs.writeShellApplication {
    name = "meme";
    runtimeInputs = [
      botPython
      pkgs.exiftool
    ];
    text = ''
      export PYTHONPATH=${gpuLockRoot}:${memeSrc}''${PYTHONPATH:+:$PYTHONPATH}
      exec ${botPython}/bin/python3 ${memeSrc}/cli.py "$@"
    '';
  };

  vfind = pkgs.writeShellApplication {
    name = "vfind";
    runtimeInputs = [
      botPython
      pkgs.exiftool
    ];
    text = ''
      exec ${botPython}/bin/python3 ${memeSrc}/find.py "$@"
    '';
  };

  meme-server = pkgs.writeShellApplication {
    name = "meme-server";
    runtimeInputs = [
      botPython
      pkgs.exiftool
    ];
    text = ''
      export PYTHONPATH=${gpuLockRoot}:${memeSrc}''${PYTHONPATH:+:$PYTHONPATH}
      exec ${botPython}/bin/python3 ${memeSrc}/server.py "$@"
    '';
  };
in
{
  inherit meme vfind meme-server;
}
