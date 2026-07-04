{ stdenv, fetchurl, autoPatchelfHook, autoAddDriverRunpath, zstd, vulkan-loader, makeWrapper }:

stdenv.mkDerivation (finalAttrs: {
  pname = "ollama-bin";
  version = "0.31.1";

  src = fetchurl {
    url = "https://github.com/ollama/ollama/releases/download/v${finalAttrs.version}/ollama-linux-amd64.tar.zst";
    hash = "sha256-0pc4HvwTZFH2+rud1kSmf3D+UcFoFaDEqV/w4yejr7Q=";
  };

  sourceRoot = ".";

  nativeBuildInputs = [ autoPatchelfHook autoAddDriverRunpath zstd makeWrapper ];
  buildInputs = [ stdenv.cc.cc.lib vulkan-loader ];

  autoPatchelfIgnoreMissingDeps = [ "libcuda.so.1" ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r bin lib $out/
    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/ollama \
      --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib
  '';

  meta = {
    description = "Upstream prebuilt ollama with bundled CUDA runtime; fetched, never compiled";
    mainProgram = "ollama";
    platforms = [ "x86_64-linux" ];
  };
})
