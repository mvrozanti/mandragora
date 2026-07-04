{ stdenvNoCC, fontforge, iosevkaNerd }:

stdenvNoCC.mkDerivation {
  pname = "iosevka-nerd-font-nvidia";
  version = iosevkaNerd.version or "patched";

  dontUnpack = true;
  dontConfigure = true;
  dontInstall = true;
  dontFixup = true;

  nativeBuildInputs = [ fontforge ];

  buildPhase = ''
    runHook preBuild
    src=${iosevkaNerd}/share/fonts/truetype/NerdFonts/Iosevka
    dst=$out/share/fonts/truetype/NerdFonts/Iosevka
    mkdir -p "$dst"
    for f in "$src"/*.ttf; do
      base=$(basename "$f")
      if ! fontforge -lang=py -script ${../../snippets/add-nvidia-glyph.py} \
            "$f" ${../../snippets/nvidia.svg} "$dst/$base" 2>/dev/null; then
        echo "war: patch failed for $base, copying original" >&2
        cp "$f" "$dst/$base"
      fi
    done
    runHook postBuild
  '';
}
