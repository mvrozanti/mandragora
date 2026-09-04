{ pkgs }:

let
  upstreamSrc = pkgs.fetchFromGitHub {
    owner = "mvrozanti";
    repo = "vtag";
    rev = "f01b62409fe0ce18b7b357806f67e06cc38a18cb";
    sha256 = "sha256-ZtYSaO7JPy8hnRN5kpbKERZbng5qaWvzH8DIqEv10wc=";
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
