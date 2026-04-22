{ pkgs, lib, ... }:

let
  baritone = pkgs.fetchurl {
    url = "https://maven.meteordev.org/snapshots/meteordevelopment/baritone/1.20.6-SNAPSHOT/baritone-1.20.6-20240609.142719-1.jar";
    hash = "sha256-u0+IlI2/eNE/GAXk0D8FPGazmGmWitw+K+9jGJy6zqY=";
  };

  instanceCfg = pkgs.writeText "meteor-instance.cfg" ''
    [General]
    ConfigVersion=1.3
    InstanceType=OneSix
    iconKey=default
    name=Meteor 1.20.5
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
        cachedVersion = "1.20.5";
        important = true;
        uid = "net.minecraft";
        version = "1.20.5";
      }
      {
        cachedName = "Intermediary Mappings";
        cachedRequires = [ { equals = "1.20.5"; uid = "net.minecraft"; } ];
        cachedVersion = "1.20.5";
        cachedVolatile = true;
        dependencyOnly = true;
        uid = "net.fabricmc.intermediary";
        version = "1.20.5";
      }
      {
        cachedName = "Fabric Loader";
        cachedRequires = [ { uid = "net.fabricmc.intermediary"; } ];
        cachedVersion = "0.19.2";
        uid = "net.fabricmc.fabric-loader";
        version = "0.19.2";
      }
    ];
  });
in
{
  home.activation.setupMeteorInstance = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    INST="$HOME/.local/share/PrismLauncher/instances/meteor-1.20.5"
    MODS="$INST/minecraft/mods"

    if [ ! -d "$INST" ]; then
      $DRY_RUN_CMD mkdir -p "$MODS"
      $DRY_RUN_CMD install -m 0644 ${instanceCfg} "$INST/instance.cfg"
      $DRY_RUN_CMD install -m 0644 ${mmcPackJson} "$INST/mmc-pack.json"
    fi

    $DRY_RUN_CMD mkdir -p "$MODS"
    $DRY_RUN_CMD ln -sf ${baritone} "$MODS/baritone.jar"

    FORK_JAR=$(ls "$HOME/dev/meteor-client/build/libs"/meteor-client-*.jar 2>/dev/null | sort -V | tail -1)
    if [ -n "$FORK_JAR" ]; then
      $DRY_RUN_CMD ln -sf "$FORK_JAR" "$MODS/meteor-client.jar"
    else
      echo "Note: fork JAR not found - run ./gradlew build in ~/dev/meteor-client" >&2
    fi
  '';
}
