{
  stdenvNoCC,
  neomutt,
  python3,
}:
stdenvNoCC.mkDerivation {
  pname = "mutt-oauth2";
  inherit (neomutt) version;
  dontUnpack = true;
  buildInputs = [ python3 ];
  patches = [ ./public-client-plaintext.patch ];
  prePatch = ''
    cp ${neomutt}/share/neomutt/oauth2/mutt_oauth2.py .
    chmod u+w mutt_oauth2.py
  '';
  patchFlags = [ "-p1" ];
  installPhase = ''
    install -Dm755 mutt_oauth2.py $out/bin/mutt-oauth2
    patchShebangs $out/bin
  '';
}
