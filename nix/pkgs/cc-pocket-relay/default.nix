{
  lib,
  stdenv,
  fetchFromGitHub,
  jdk17,
  gradle_9,
  makeWrapper,
}:

let
  version = "2.1.0";
  pname = "cc-pocket-relay";
  gradle = gradle_9.override { javaToolchains = [ jdk17 ]; };
  mitmCache = gradle.fetchDeps {
    inherit pname;
    data = ./deps.json;
  };
in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchFromGitHub {
    owner = "heypandax";
    repo = "pairlet";
    rev = "v${version}";
    hash = "sha256-nr0JQiSYmA0g62b3xtYpyZBuHd2nMxZ+Tny33VsBUuU=";
  };

  nativeBuildInputs = [
    jdk17
    gradle
    makeWrapper
  ];

  inherit mitmCache;

  postPatch = ''
    sed -i -e '/include(":mobile:/d' -e '/include(":daemon")/d' settings.gradle.kts
  '';

  gradleBuildTask = ":relay:installDist";
  gradleUpdateTask = ":relay:installDist";

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r relay/build/install/cc-pocket-relay/. "$out/"
    wrapProgram "$out/bin/cc-pocket-relay" --prefix PATH : ${jdk17}/bin
    runHook postInstall
  '';

  passthru.updateScript = mitmCache.updateScript;

  meta = with lib; {
    description = "Pairlet relay: zero-knowledge ciphertext broker for remote Claude Code control";
    homepage = "https://github.com/heypandax/pairlet";
    license = licenses.mit;
    mainProgram = "cc-pocket-relay";
    platforms = [ "x86_64-linux" ];
  };
}
