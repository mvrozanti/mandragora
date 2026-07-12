{
  lib,
  stdenvNoCC,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_22,
  makeWrapper,
  cacert,
}:

let
  src = fetchFromGitHub {
    owner = "Arindam200";
    repo = "cc-lens";
    rev = "db90effa1b4f3452b6660e7ff6896901b1efdc56";
    hash = "sha256-+TYgbjYPbpVOoJvoCxIjfKj1FKWBcn+jU7EGRNriqCs=";
  };

  googleFontsRaw = stdenvNoCC.mkDerivation {
    pname = "cc-lens-google-fonts-raw";
    version = "unstable-2026-06-19";
    nativeBuildInputs = [
      nodejs_22
      cacert
    ];
    dontUnpack = true;
    buildPhase = ''
      runHook preBuild
      node ${./fetch-google-fonts.js}
      runHook postBuild
    '';
    dontInstall = true;
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-+2bXaKPnBpmX6gwRJKtajjUdUFc9dMLl2+9KYXYO1vQ=";
  };

  googleFonts = stdenvNoCC.mkDerivation {
    pname = "cc-lens-google-fonts";
    version = "unstable-2026-06-19";
    dontUnpack = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r ${googleFontsRaw}/fonts $out/fonts
      substitute ${googleFontsRaw}/mock.json $out/mock.json \
        --replace-fail '@FONTS_DIR@' "$out/fonts"
      runHook postInstall
    '';
  };
in
buildNpmPackage {
  pname = "cc-lens";
  version = "unstable-2026-06-19";

  inherit src;

  npmDepsHash = "sha256-RFvtuKr98ayBjKJ+wilSI89qni48FaBD7jjzXFg0iRU=";

  nodejs = nodejs_22;

  nativeBuildInputs = [ makeWrapper ];

  env = {
    NEXT_TELEMETRY_DISABLED = "1";
    NEXT_FONT_GOOGLE_MOCKED_RESPONSES = "${googleFonts}/mock.json";
  };

  dontNpmPrune = true;

  buildPhase = ''
    runHook preBuild
    node_modules/.bin/next build --webpack
    node bin/prepare-standalone.js
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/cc-lens
    cp -r .next/standalone/. $out/lib/cc-lens/

    makeWrapper ${nodejs_22}/bin/node $out/bin/cc-lens-server \
      --add-flags $out/lib/cc-lens/server.js

    runHook postInstall
  '';

  meta = {
    description = "Claude Code Lens — local analytics dashboard for ~/.claude usage, costs, and sessions";
    homepage = "https://github.com/Arindam200/cc-lens";
    license = lib.licenses.mit;
    mainProgram = "cc-lens-server";
    platforms = lib.platforms.linux;
  };
}
