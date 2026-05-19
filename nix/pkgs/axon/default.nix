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
  duckdbVersion = "1.1.3";

  duckdbLinux = fetchurl {
    url = "https://github.com/duckdb/duckdb/releases/download/v${duckdbVersion}/libduckdb-linux-amd64.zip";
    hash = "sha256-e/cIV+ijnuelx3q06S7gbYScxNB9ABnMYBewKJ5KBow=";
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "axon";
  version = "0.5.11-unstable-2026-05-18";

  src = fetchgit {
    url = "https://github.com/HideakiSolutions/axon.git";
    rev = "9fb25cc7e2881ddd485b67e4778f4b70b726ae1b";
    fetchSubmodules = true;
    hash = "sha256-GwSGqfWzyVOIMHETXEnJ2zPFH+wMqlHSkulOstTAAXk=";
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

    for so in bin/libllama.so bin/libggml*.so*; do
      [ -e "$so" ] && install -Dm755 "$so" "$out/lib/$(basename "$so")"
    done

    mkdir -p $out/share/axon/hooks $out/share/axon/scripts
    cp -r ../scripts/hooks/* $out/share/axon/hooks/
    cp ../scripts/install.sh $out/share/axon/scripts/install.sh

    runHook postInstall
  '';

  # autoPatchelfHook fixes libc / libstdc++ links; we add $out/lib so axon
  # finds the bundled libduckdb.so and the llama/ggml shared libs at runtime.
  appendRunpaths = [ "$out/lib" ];

  postFixup = ''
    wrapProgram $out/bin/axon \
      --prefix LD_LIBRARY_PATH : "$out/lib"
  '';

  meta = {
    description = "Local MCP context engine for AI coding agents — surgical context capsules via tree-sitter + DuckDB + llama.cpp";
    homepage = "https://github.com/HideakiSolutions/axon";
    license = lib.licenses.mit;
    mainProgram = "axon";
    platforms = [ "x86_64-linux" ];
  };
})
