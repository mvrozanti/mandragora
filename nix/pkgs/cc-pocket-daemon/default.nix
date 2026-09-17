{
  lib,
  stdenv,
  fetchurl,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "cc-pocket-daemon";
  version = "2.1.0";

  src = fetchurl {
    url = "https://github.com/heypandax/pairlet/releases/download/v${finalAttrs.version}/cc-pocket-daemon-${finalAttrs.version}-linux-x86_64.tar.gz";
    hash = "sha256-u9tj2c8lRKE3FmLQtTXZCqyvA+DI1zPeE9RJBMP8l9k=";
  };

  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r . $out/
    runHook postInstall
  '';

  meta = {
    description = "Pairlet daemon that drives the local Claude Code CLI for remote control";
    homepage = "https://github.com/heypandax/pairlet";
    license = lib.licenses.mit;
    mainProgram = "cc-pocket-daemon";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
})
