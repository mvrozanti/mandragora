{
  lib,
  stdenv,
  fetchgit,
  fetchurl,
  cmake,
  unzip,
  autoPatchelfHook,
  makeWrapper,
}:
# axon ships a CMake build that vendors llama.cpp + tree-sitter grammars as
# git submodules and consumes a prebuilt libduckdb.so from third_party/duckdb/lib/.
# The .so is checked into the upstream repo for Linux but git-stripped by
# fetchgit's normalisation — so we stage the official DuckDB release zip into
# the expected path before configure. Pinned to the same DuckDB version axon's
# build.yml uses (AXON_DUCKDB_VERSION).
let
  duckdbVersion = "1.2.2";

  duckdbLinux = fetchurl {
    url = "https://github.com/duckdb/duckdb/releases/download/v${duckdbVersion}/libduckdb-linux-amd64.zip";
    hash = "sha256-kbBvjUvKRxurT0bGdq4qWMnKGJh9DsPSX9laq6+e7z4=";
  };

  # Embedding model for semantic search / `axon capsule`. Without it axon
  # falls back to graph-only ranking and `capsule` exits with "model not
  # found". Pinned to the same Q4_K_M quant the upstream README recommends.
  embeddingModel = fetchurl {
    url = "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q4_K_M.gguf";
    hash = "sha256-1OOIiU4JzzgW6LCJbYHSZbVeep//mrA/6L9O9eESlaw=";
  };
in
stdenv.mkDerivation (_finalAttrs: {
  pname = "axon";
  version = "1.2.1";

  src = fetchgit {
    url = "https://github.com/HideakiSolutions/axon.git";
    rev = "c3481780f2eafae912a31a3ead28443069e898e4";
    fetchSubmodules = true;
    hash = "sha256-5zYwopP2dbBtgxY1s5VTsb1cKqt6KPFx3tbkSB2WpVA=";
  };

  nativeBuildInputs = [
    cmake
    unzip
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    stdenv.cc.cc.lib
  ];

  postPatch = ''
    mkdir -p third_party/duckdb/lib
    unzip -o ${duckdbLinux} -d third_party/duckdb/lib/
    test -f third_party/duckdb/lib/libduckdb.so
  '';

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DAXON_BUILD_TESTS=OFF"
    "-DGGML_NATIVE=OFF"
  ];

  installPhase = ''
    runHook preInstall

    install -Dm755 axon $out/bin/axon

    install -Dm644 ../third_party/duckdb/lib/libduckdb.so $out/lib/libduckdb.so

    # llama.cpp emits versioned sonames + .so symlinks under build/bin.
    # cp -P preserves the symlink graph so dynamic linker can hop libllama.so
    # → libllama.so.0 → libllama.so.0.x.y just like in the upstream tarball.
    mkdir -p $out/lib
    find bin -maxdepth 1 \( -name 'lib*.so*' -o -name 'lib*.dylib' \) -exec cp -P {} $out/lib/ \;

    mkdir -p $out/share/axon/hooks $out/share/axon/scripts $out/share/axon/models
    cp -r ../scripts/hooks/* $out/share/axon/hooks/
    cp ../scripts/install.sh $out/share/axon/scripts/install.sh
    install -Dm644 ${embeddingModel} $out/share/axon/models/nomic-embed-text-v1.5.Q4_K_M.gguf

    runHook postInstall
  '';

  # CMakeLists sets CMAKE_BUILD_RPATH to the sandbox source tree so the binary
  # can resolve libduckdb.so during the build's test run; llama.cpp's own
  # subbuild does the same for libllama/libggml. Both linger in the final
  # binary as `/build/source/...` references which nix rejects post-install.
  # Strip them and pin RPATH to $out/lib (where we copied the runtime .so set).
  preFixup = ''
    for f in $out/bin/axon $out/lib/*.so*; do
      [ -L "$f" ] && continue
      patchelf --set-rpath "$out/lib" "$f"
    done
  '';

  postFixup = ''
    wrapProgram $out/bin/axon \
      --prefix LD_LIBRARY_PATH : "$out/lib" \
      --set-default AXON_EMBEDDING_MODEL "$out/share/axon/models/nomic-embed-text-v1.5.Q4_K_M.gguf"
  '';

  meta = {
    description = "Local MCP context engine for AI coding agents — surgical context capsules via tree-sitter + DuckDB + llama.cpp";
    homepage = "https://github.com/HideakiSolutions/axon";
    license = lib.licenses.mit;
    mainProgram = "axon";
    platforms = [ "x86_64-linux" ];
  };
})
