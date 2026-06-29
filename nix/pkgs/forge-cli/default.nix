{ lib, buildNpmPackage, makeWrapper, nodejs, pkg-config, libsecret, python3 }:
buildNpmPackage {
  pname = "forge-cli";
  version = "12.22.0";

  src = ./.;

  npmDepsHash = "sha256-1Qzk/PiBI6olbNSW9GQN8OG+fUVrL6mNBCYk6pLbgoY=";
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
