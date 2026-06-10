{
  lib,
  stdenv,
  fetchzip,
  autoPatchelfHook,
  makeWrapper,
  bubblewrap,
  procps,
  socat,
}:
# claude-code 2.1.116+ ships as a native ELF binary via platform-specific
# npm optional deps. We fetch the matching architecture binary directly and
# bypass npm.
let
  archMap = {
    "x86_64-linux" = {
      npmArch = "linux-x64";
      hash = "sha256-x3xV1+ELl0meuzwNJT2nwGRelqU4F0yarvB2vVvvhCM=";
    };
    "aarch64-linux" = {
      npmArch = "linux-arm64";
      hash = "sha256-bxIsR192xpJdy1ITWsBmKrpcZy6wy4mr3ym5/T47Leg=";
    };
  };
  arch = archMap.${stdenv.hostPlatform.system} or (throw "claude-code: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "claude-code";
  version = "2.1.172";

  src = fetchzip {
    url = "https://registry.npmjs.org/@anthropic-ai/claude-code-${arch.npmArch}/-/claude-code-${arch.npmArch}-${finalAttrs.version}.tgz";
    hash = arch.hash;
  };

  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];
  buildInputs = [ stdenv.cc.libc ];

  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 claude $out/lib/claude-code/claude
    runHook postInstall
  '';

  postFixup = ''
    makeWrapper $out/lib/claude-code/claude $out/bin/claude \
      --set DISABLE_AUTOUPDATER 1 \
      --set-default FORCE_AUTOUPDATE_PLUGINS 1 \
      --set DISABLE_INSTALLATION_CHECKS 1 \
      --unset DEV \
      --prefix PATH : ${
        lib.makeBinPath [
          procps
          bubblewrap
          socat
        ]
      }
  '';

  meta = {
    description = "Agentic coding tool that lives in your terminal, understands your codebase, and helps you code faster";
    homepage = "https://github.com/anthropics/claude-code";
    downloadPage = "https://www.npmjs.com/package/@anthropic-ai/claude-code";
    license = lib.licenses.unfree;
    mainProgram = "claude";
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
})
