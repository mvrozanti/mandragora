{ pkgs, lib, ... }:

let
  seus = pkgs.fetchurl {
    url = "https://master.dl.sourceforge.net/project/shaderbear/SEUS-Renewed-v1.0.1.zip";
    hash = "sha256-dqH/bA14J+zQhX5am1KYM38jJmJ2er8PARFUyFttqO8=";
  };

  bliss = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/ZvMtQlho/versions/kC2Y8q1P/Bliss_v2.1.2_%28Chocapic13_Shaders_edit%29.zip";
    hash = "sha256-9B25KsxYX+n/4MwSTW7K6ifO+d7ZESnrwqjmAiaUeyw=";
  };

  sildurs-vibrant = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/z8EjLYqN/versions/7Bij7xAf/Sildur%27s%20Vibrant%20Shaders%20v1.56%20Extreme.zip";
    hash = "sha256-xvN1vrzLvob4gnKTisBcCFdXRFOwJiFixNGk4JDn18w=";
  };

  rethinking-voxels = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/kmwfVOoi/versions/cpD4esk9/rethinking-voxels_r0.1-beta9.zip";
    hash = "sha256-qM2dQzjH09H//sxFJTSKMeo9IZ7zE4LFHV3cO0sBFOE=";
  };

  complementary-reimagined = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/HVnmMxH1/versions/yCCduG44/ComplementaryReimagined_r5.8.1.zip";
    hash = "sha256-PxzTiecXsuYvWO3/IiBZucYN5xsUu0m1F+tYMYzjWxU=";
  };

  iris = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/YL57xq9U/versions/fDpuVzVr/iris-fabric-1.10.7%2Bmc1.21.11.jar";
    hash = "sha256-WMVdoYGJyRpJ+EfTzuRRYzojtXX7acDFtl3bJ0Q2yxk=";
  };

  sodium = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/AANobbMI/versions/NFkjnzWE/sodium-fabric-0.8.12%2Bmc1.21.11.jar";
    hash = "sha256-AJKZdI8ZL2JG/WdZomME8P6gbzQSz/Ui0dUz4rjbgXY=";
  };

  baritone = pkgs.fetchurl {
    url = "https://maven.meteordev.org/snapshots/meteordevelopment/baritone/1.21.11-SNAPSHOT/baritone-1.21.11-20260103.131549-1.jar";
    hash = "sha256-Pox6uGt8AUj4cRyi58tghxLbwqlyU94PEx7D20GivTw=";
  };

  distant-horizons = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/uCdwusMi/versions/mVAIpNz9/DistantHorizons-3.0.2-b-1.21.11-fabric-neoforge.jar";
    hash = "sha256-e09suXafrxNcoURXKq4XJKESAPzVKQbzEK3PmSKZWnk=";
  };

  instanceCfg = pkgs.writeText "meteor-instance.cfg" ''
    [General]
    ConfigVersion=1.3
    InstanceType=OneSix
    iconKey=default
    name=chicken-client 1.21.11
  '';

  mmcPackJson = pkgs.writeText "meteor-mmc-pack.json" (builtins.toJSON {
    formatVersion = 1;
    components = [
      {
        cachedName = "LWJGL 3";
        cachedVersion = "3.3.3";
        cachedVolatile = true;
        dependencyOnly = true;
        uid = "org.lwjgl3";
        version = "3.3.3";
      }
      {
        cachedName = "Minecraft";
        cachedRequires = [ { suggests = "3.3.3"; uid = "org.lwjgl3"; } ];
        cachedVersion = "1.21.11";
        important = true;
        uid = "net.minecraft";
        version = "1.21.11";
      }
      {
        cachedName = "Intermediary Mappings";
        cachedRequires = [ { equals = "1.21.11"; uid = "net.minecraft"; } ];
        cachedVersion = "1.21.11";
        cachedVolatile = true;
        dependencyOnly = true;
        uid = "net.fabricmc.intermediary";
        version = "1.21.11";
      }
      {
        cachedName = "Fabric Loader";
        cachedRequires = [ { uid = "net.fabricmc.intermediary"; } ];
        cachedVersion = "0.18.2";
        uid = "net.fabricmc.fabric-loader";
        version = "0.18.2";
      }
    ];
  });

  minecraft-launcher = pkgs.writeShellScriptBin "minecraft" ''
    INSTANCE=$(find ~/.local/share/PrismLauncher/instances -name mmc-pack.json -exec ${pkgs.jq}/bin/jq -r '.components[] | select(.uid=="net.minecraft") | .version + " " + input_filename' {} + | sort -V | tail -n 1 | ${pkgs.gawk}/bin/awk '{print $2}' | xargs dirname | xargs basename)
    if [ -n "$INSTANCE" ]; then
      echo "Launching Prism Launcher instance: $INSTANCE"
      exec ${pkgs.prismlauncher}/bin/prismlauncher --launch "$INSTANCE" "$@"
    else
      echo "Error: No Prism Launcher instances found."
      exit 1
    fi
  '';
in
{
  home.packages = [ minecraft-launcher ];

  home.activation.setupMeteorInstance = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    INST="$HOME/.local/share/PrismLauncher/instances/chicken-client"
    MODS="$INST/minecraft/mods"

    if [ ! -d "$INST" ]; then
      $DRY_RUN_CMD mkdir -p "$MODS"
    $DRY_RUN_CMD ln -sf ${iris} "$MODS/iris.jar"
    $DRY_RUN_CMD ln -sf ${sodium} "$MODS/sodium.jar"
      $DRY_RUN_CMD install -m 0644 ${instanceCfg} "$INST/instance.cfg"
      $DRY_RUN_CMD install -m 0644 ${mmcPackJson} "$INST/mmc-pack.json"
    fi

    $DRY_RUN_CMD mkdir -p "$MODS"
    $DRY_RUN_CMD ln -sf ${iris} "$MODS/iris.jar"
    $DRY_RUN_CMD ln -sf ${sodium} "$MODS/sodium.jar"
    $DRY_RUN_CMD ln -sf ${baritone} "$MODS/baritone.jar"
    $DRY_RUN_CMD ln -sf ${distant-horizons} "$MODS/distant-horizons.jar"

    SHADERPACKS="$INST/minecraft/shaderpacks"
    $DRY_RUN_CMD mkdir -p "$SHADERPACKS"
    $DRY_RUN_CMD ln -sf ${seus} "$SHADERPACKS/SEUS-Renewed-v1.0.1.zip"
    $DRY_RUN_CMD ln -sf ${bliss} "$SHADERPACKS/Bliss-v2.1.2.zip"
    $DRY_RUN_CMD ln -sf ${sildurs-vibrant} "$SHADERPACKS/Sildurs-Vibrant-v1.56-Extreme.zip"
    $DRY_RUN_CMD ln -sf ${rethinking-voxels} "$SHADERPACKS/Rethinking-Voxels-r0.1-beta9.zip"
    $DRY_RUN_CMD ln -sf ${complementary-reimagined} "$SHADERPACKS/Complementary-Reimagined-r5.8.1.zip"

    FORK_JAR=""
    if [ -d "$HOME/Projects/meteor-client/build/libs" ]; then
      FORK_JAR=$(find "$HOME/Projects/meteor-client/build/libs" -name "meteor-client-*.jar" | sort -V | tail -1)
    fi
    if [ -n "$FORK_JAR" ]; then
      $DRY_RUN_CMD ln -sf "$FORK_JAR" "$MODS/meteor-client.jar"
    else
      echo "Note: run ./gradlew build in ~/Projects/meteor-client to install the mod" >&2
    fi
  '';
}
