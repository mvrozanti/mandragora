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
let
  archMap = {
    "x86_64-linux" = {
      npmArch = "linux-x64";
      hash = "sha256-H6a24ER+XHMYqOT9Get5J/Ri3nAmY82QaUuu9oXEQyk=";
    };
    "aarch64-linux" = {
      npmArch = "linux-arm64";
      hash = "sha256-LO+qfjRfxmjDyqWzLK2Zn8WwpedurP5T2RIUBHJ+S9A=";
    };
    "aarch64-darwin" = {
      npmArch = "darwin-arm64";
      hash = "sha256-u0amkzeQRhnejV90fxGWkNcIQgyV4ijoQg/E6gc6eLM=";
    };
  };
  inherit (stdenv.hostPlatform) isLinux;
  arch =
    archMap.${stdenv.hostPlatform.system}
      or (throw "claude-code: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "claude-code";
  version = "2.1.329";

  src = fetchzip {
    url = "https://registry.npmjs.org/@anthropic-ai/claude-code-${arch.npmArch}/-/claude-code-${arch.npmArch}-${finalAttrs.version}.tgz";
    inherit (arch) hash;
  };

  nativeBuildInputs = lib.optional isLinux autoPatchelfHook ++ [ makeWrapper ];
  buildInputs = lib.optional isLinux stdenv.cc.libc;

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
      --prefix PATH : ${lib.makeBinPath ([ procps ] ++ lib.optional isLinux bubblewrap ++ [ socat ])}
  '';

  meta = {
    description = "Agentic coding tool that lives in your terminal, understands your codebase, and helps you code faster";
    homepage = "https://github.com/anthropics/claude-code";
    downloadPage = "https://www.npmjs.com/package/@anthropic-ai/claude-code";
    license = lib.licenses.unfree;
    mainProgram = "claude";
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
})
