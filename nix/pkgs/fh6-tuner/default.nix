{
  stdenvNoCC,
  fetchFromGitHub,
  python3,
  makeWrapper,
}:
let
  python = python3.withPackages (
    ps: with ps; [
      numpy
      rich
      click
      mcp
    ]
  );
in
stdenvNoCC.mkDerivation {
  pname = "fh6-tuner";
  version = "0-unstable-2026-07-15";
  src = fetchFromGitHub {
    owner = "Jacobobber";
    repo = "fh6-tuner";
    rev = "3ca08158121b6fadff212a930dbb6516a4d356cd";
    hash = "sha256-qHQtKJuXD0Ky0vfrhaSMz0eADTn7+nSVtXTfH8e+n28=";
  };
  nativeBuildInputs = [ makeWrapper ];
  passthru = {
    inherit python;
  };
  postPatch = ''
    substituteInPlace mcp_server.py --replace-fail 'Path(__file__).parent / "sessions"' 'Path.cwd() / "sessions"'
    sed -i 's/default=5300/default=5301/g; s/default: 5300/default: 5301/g' main.py
  '';
  installPhase = ''
    mkdir -p $out/share/fh6-tuner $out/bin
    cp -r . $out/share/fh6-tuner
    makeWrapper ${python}/bin/python3 $out/bin/fh6-tuner \
      --add-flags "$out/share/fh6-tuner/main.py" \
      --run 'mkdir -p "$HOME/.local/state/fh6-tuner" && cd "$HOME/.local/state/fh6-tuner"'
  '';
}
