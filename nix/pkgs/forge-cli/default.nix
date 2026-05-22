{ lib, buildNpmPackage, makeWrapper, nodejs, pkg-config, libsecret, python3 }:
buildNpmPackage {
  pname = "forge-cli";
  version = "12.20.1";

  src = ./.;

  npmDepsHash = "sha256-1BRyuZ6i+vy7pGK413SQJB8kXBm4bCRoywGmMDBjyzA=";
  npmDepsFetcherVersion = 2;
  npmFlags = [ "--legacy-peer-deps" ];
  makeCacheWritable = true;

  nativeBuildInputs = [ pkg-config python3 makeWrapper ];
  buildInputs = [ libsecret ];

  dontNpmBuild = true;
  inherit nodejs;

  postInstall = ''
    mkdir -p $out/bin
    makeWrapper ${nodejs}/bin/node $out/bin/forge \
      --add-flags $out/lib/node_modules/forge-cli-wrapper/node_modules/@forge/cli/out/bin/cli.js \
      --prefix PATH : ${lib.makeBinPath [ nodejs ]}
  '';

  meta = {
    description = "Atlassian Forge CLI — build, deploy, and manage Forge apps";
    homepage = "https://developer.atlassian.com/platform/forge/";
    license = lib.licenses.unfree;
    mainProgram = "forge";
    platforms = lib.platforms.linux;
  };
}
