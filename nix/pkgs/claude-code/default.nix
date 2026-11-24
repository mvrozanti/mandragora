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
      hash = "sha256-106Q47+nQ/j42pJ2PUd+/4rd/LuO1KNMH2Vs3GWeMAU=";
    };
    "aarch64-linux" = {
      npmArch = "linux-arm64";
      hash = "sha256-SGMZupsBA8G6URWupCoxxKWJU6i4cyLFunV0a9CxY7c=";
    };
    "aarch64-darwin" = {
      npmArch = "darwin-arm64";
      hash = "sha256-rWY0nuqoAguPo7YyOAmXDzkQ/CJijHvYuI5Hf4Hxrrc=";
    };
  };
  inherit (stdenv.hostPlatform) isLinux;
  arch =
    archMap.${stdenv.hostPlatform.system}
      or (throw "claude-code: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "claude-code";
  version = "2.1.331";

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
