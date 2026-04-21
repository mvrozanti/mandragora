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
# npm optional deps. We fetch the linux-x64 binary directly and bypass npm.
stdenv.mkDerivation (finalAttrs: {
  pname = "claude-code";
  version = "2.1.116";

  # The actual native binary package
  src = fetchzip {
    url = "https://registry.npmjs.org/@anthropic-ai/claude-code-linux-x64/-/claude-code-linux-x64-${finalAttrs.version}.tgz";
    hash = "sha256-QEjJ4CRk35TubDNW02Dzcu+EMRLLndJUXJeP3BFT3b8=";
  };

  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];
  buildInputs = [ stdenv.cc.libc ];

  dontBuild = true;

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
    platforms = [ "x86_64-linux" ];
  };
})
