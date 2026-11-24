{ pkgs }:

let
  upstreamSrc = pkgs.fetchFromGitHub {
    owner = "mvrozanti";
    repo = "vtag";
    rev = "88d5d2ecb53fcf585b4ee6310f910ef10a9ae6b1";
    sha256 = "sha256-S3DH+ElmMvP+EpOyoPVAWdGtSbPvd1Gdi9E5bmMMUW4=";
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
    patch -p1 -d $out < ${../snippets/meme-sidecar-roots.patch}
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
