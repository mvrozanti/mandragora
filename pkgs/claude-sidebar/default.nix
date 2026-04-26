{
  lib,
  stdenv,
  fetchFromGitHub,
  zip,
}:

stdenv.mkDerivation {
  pname = "claude-sidebar";
  version = "1.1";

  src = fetchFromGitHub {
    owner = "drudge";
    repo = "firefox-claude-sidebar-addon";
    rev = "2960c2a9660118433b3c89d634ca5ac3da63ccf5";
    sha256 = "0vaabwqc6a9dsfv21fhy9cp64w3sf20ja84fppdzbvcml9qmkl7n";
  };

  nativeBuildInputs = [ zip ];

  buildPhase = ''
    runHook preBuild
    zip -r claude-sidebar.xpi . -x "*.git*" "build.sh" "README.md" "CLAUDE.md" ".gitignore" ".github/*" "web-ext-config.mjs"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}
    cp claude-sidebar.xpi $out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/{d1399635-a397-4ee7-bc61-d917bd5e1010}.xpi
    runHook postInstall
  '';

  meta = {
    description = "Access Claude AI directly in your Firefox sidebar";
    homepage = "https://github.com/drudge/firefox-claude-sidebar-addon";
    license = lib.licenses.asl20;
    platforms = lib.platforms.all;
  };
}
