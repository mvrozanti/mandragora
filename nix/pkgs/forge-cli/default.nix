{ lib, buildNpmPackage, nodejs, pkg-config, libsecret, python3 }:
buildNpmPackage {
  pname = "forge-cli";
  version = "12.20.1";

  src = ./.;

  npmDepsHash = "sha256-1BRyuZ6i+vy7pGK413SQJB8kXBm4bCRoywGmMDBjyzA=";
  npmDepsFetcherVersion = 2;
  npmFlags = [ "--legacy-peer-deps" ];
  makeCacheWritable = true;

  nativeBuildInputs = [ pkg-config python3 ];
  buildInputs = [ libsecret ];

  dontNpmBuild = true;
  inherit nodejs;

  postInstall = ''
    mkdir -p $out/bin
    ln -s $out/lib/node_modules/forge-cli-wrapper/node_modules/@forge/cli/out/bin/cli.js $out/bin/forge
    chmod +x $out/lib/node_modules/forge-cli-wrapper/node_modules/@forge/cli/out/bin/cli.js
  '';

  meta = {
    description = "Atlassian Forge CLI — build, deploy, and manage Forge apps";
    homepage = "https://developer.atlassian.com/platform/forge/";
    license = lib.licenses.unfree;
    mainProgram = "forge";
    platforms = lib.platforms.linux;
  };
}
