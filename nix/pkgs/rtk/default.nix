{
  lib,
  stdenv,
  fetchurl,
}:
let
  targets = {
    "x86_64-linux" = {
      triple = "x86_64-unknown-linux-musl";
      hash = "sha256-Pft6BWNqaGh7ocWqaW+o1fy0lER97YbZ64uItxAKN8Y=";
    };
    "aarch64-darwin" = {
      triple = "aarch64-apple-darwin";
      hash = "sha256-meIKWYR97btkAyo/eYXy/pWfy5Z02Or5QPxYoYnifso=";
    };
  };
  target =
    targets.${stdenv.hostPlatform.system}
      or (throw "rtk: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "rtk";
  version = "0.37.2";

  src = fetchurl {
    url = "https://github.com/rtk-ai/rtk/releases/download/v${finalAttrs.version}/rtk-${target.triple}.tar.gz";
    inherit (target) hash;
  };

  sourceRoot = ".";
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 rtk $out/bin/rtk
    runHook postInstall
  '';

  meta = {
    description = "CLI proxy that reduces LLM token consumption by 60-90% on common dev commands";
    homepage = "https://github.com/rtk-ai/rtk";
    license = lib.licenses.mit;
    mainProgram = "rtk";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = builtins.attrNames targets;
  };
})
