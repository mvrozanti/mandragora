{ pkgs }:

let
  upstreamSrc = pkgs.fetchFromGitHub {
    owner = "mvrozanti";
    repo = "vtag";
    rev = "d567c2949bcf0aeff53e245ee8e027d99274bce9";
    sha256 = "sha256-JBB9S4dlWK4PPlW9EXb+z2DiW1DNgnAruAiH2Rmr/vg=";
  };

  hubStatic = ../hosts/mandragora-vps/compose/hub/static;
  designSystem = map (name: hubStatic + "/${name}") [
    "theme.css"
    "theme.js"
    "components.css"
  ];

  memeSrc = pkgs.runCommand "meme-src" { } ''
    cp -r ${upstreamSrc} $out
    chmod -R u+w $out
    cp ${builtins.concatStringsSep " " designSystem} $out/webui/static/
    substituteInPlace $out/webui/static/index.html \
      --replace-fail '<title>vtag · mvr.ac</title>' '<title>meme · mvr.ac</title>' \
      --replace-fail '<span class="brand">vtag</span>' '<span class="brand">meme</span>'
    substituteInPlace $out/cli.py \
      --replace-fail 'prog="vtag"' 'prog="meme"' \
      --replace-fail '"""vtag CLI:' '"""meme CLI:' \
      --replace-fail 'cmd = ["vtag", "tag"]' 'cmd = ["meme", "tag"]'
  '';
  gpuLockRoot = ../../.local/share/gpu-lock;
  memePython = import ./meme-python.nix { inherit pkgs; };

  meme = pkgs.writeShellApplication {
    name = "meme";
    runtimeInputs = [
      memePython
      pkgs.exiftool
    ];
    text = ''
      export PYTHONPATH=${gpuLockRoot}:${memeSrc}''${PYTHONPATH:+:$PYTHONPATH}
      exec ${memePython}/bin/python3 ${memeSrc}/cli.py "$@"
    '';
  };

  vfind = pkgs.writeShellApplication {
    name = "vfind";
    runtimeInputs = [
      memePython
      pkgs.exiftool
    ];
    text = ''
      exec ${memePython}/bin/python3 ${memeSrc}/find.py "$@"
    '';
  };

  meme-server = pkgs.writeShellApplication {
    name = "meme-server";
    runtimeInputs = [
      memePython
      pkgs.exiftool
    ];
    text = ''
      export PYTHONPATH=${gpuLockRoot}:${memeSrc}''${PYTHONPATH:+:$PYTHONPATH}
      exec ${memePython}/bin/python3 ${memeSrc}/server.py "$@"
    '';
  };
in
{
  inherit meme vfind meme-server;
}
