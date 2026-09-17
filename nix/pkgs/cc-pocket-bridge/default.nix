{
  lib,
  stdenvNoCC,
  buildNpmPackage,
  fetchurl,
  nodejs_22,
  makeWrapper,
}:

let
  version = "1.83.0";

  tarball = fetchurl {
    url = "https://registry.npmjs.org/@ccpocket/bridge/-/bridge-${version}.tgz";
    hash = "sha256-gxr04j5RPPLJttKjQBsNQBgwUZVHERap4JxXviwglD0=";
  };

  src = stdenvNoCC.mkDerivation {
    pname = "cc-pocket-bridge-src";
    inherit version;
    src = tarball;
    dontUnpack = true;
    buildPhase = ''
      runHook preBuild
      tar xzf "$src" --strip-components=1 -C .
      cp ${./package-lock.json} package-lock.json
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r . "$out"
      runHook postInstall
    '';
  };
in
buildNpmPackage {
  pname = "cc-pocket-bridge";
  inherit version src;

  npmDepsHash = "sha256-7iLxhHdmiLkf+mW0cpBxn2KR/G0vIElvhO4rq5p76JI=";

  nodejs = nodejs_22;

  nativeBuildInputs = [ makeWrapper ];

  buildPhase = ''
    runHook preBuild
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/cc-pocket-bridge"
    cp -r dist node_modules "$out/lib/cc-pocket-bridge/"
    cp package.json "$out/lib/cc-pocket-bridge/"
    makeWrapper ${nodejs_22}/bin/node "$out/bin/cc-pocket-bridge" \
      --add-flags "$out/lib/cc-pocket-bridge/dist/cli.js"
    runHook postInstall
  '';

  meta = {
    description = "CC Pocket bridge server (K9i-0/ccpocket): connects Claude Agent SDK and Codex CLI sessions to the mobile app over WebSocket";
    homepage = "https://github.com/K9i-0/ccpocket";
    license = lib.licenses.mit;
    mainProgram = "cc-pocket-bridge";
    platforms = lib.platforms.linux;
  };
}
