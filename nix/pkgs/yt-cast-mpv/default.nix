{
  lib,
  buildNpmPackage,
  nodejs_22,
  makeWrapper,
  mpv,
  yt-dlp,
}:

buildNpmPackage {
  pname = "yt-cast-mpv";
  version = "1.0.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./package.json
      ./package-lock.json
      ./index.js
      ./mpv.js
      ./player.js
      ./datastore.js
    ];
  };

  npmDepsHash = "sha256-1ouFpakFEz+npzmYzcvL9GMinx1XKjDdRfKIPc8AGkE=";

  nodejs = nodejs_22;

  nativeBuildInputs = [ makeWrapper ];

  dontNpmBuild = true;

  installPhase = ''
    runHook preInstall

    patch -p1 -d node_modules/yt-cast-receiver < ${./adopt-active-session.patch}
    patch -p1 -d node_modules/yt-cast-receiver < ${./single-video-cast.patch}

    mkdir -p $out/lib/yt-cast-mpv
    cp -r node_modules package.json index.js mpv.js player.js datastore.js $out/lib/yt-cast-mpv/

    makeWrapper ${nodejs_22}/bin/node $out/bin/yt-cast-mpv \
      --add-flags $out/lib/yt-cast-mpv/index.js \
      --prefix PATH : ${
        lib.makeBinPath [
          mpv
          yt-dlp
        ]
      }

    runHook postInstall
  '';

  meta = {
    description = "YouTube Cast (DIAL) receiver that plays casted videos through mpv";
    homepage = "https://github.com/patrickkfkan/yt-cast-receiver";
    license = lib.licenses.mit;
    mainProgram = "yt-cast-mpv";
    platforms = lib.platforms.linux;
  };
}
