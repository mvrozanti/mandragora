{ pkgs, lib, ... }:

let
  seus = pkgs.fetchurl {
    url = "https://master.dl.sourceforge.net/project/shaderbear/SEUS-Renewed-v1.0.1.zip";
    hash = "sha256-dqH/bA14J+zQhX5am1KYM38jJmJ2er8PARFUyFttqO8=";
  };

  baritone = pkgs.fetchurl {
    url = "https://maven.meteordev.org/snapshots/meteordevelopment/baritone/1.21.11-SNAPSHOT/baritone-1.21.11-20260103.131549-1.jar";
    hash = "sha256-Pox6uGt8AUj4cRyi58tghxLbwqlyU94PEx7D20GivTw=";
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
in
{
  home.activation.setupMeteorInstance = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    INST="$HOME/.local/share/PrismLauncher/instances/chicken-client"
    MODS="$INST/minecraft/mods"

    if [ ! -d "$INST" ]; then
      $DRY_RUN_CMD mkdir -p "$MODS"
      $DRY_RUN_CMD install -m 0644 ${instanceCfg} "$INST/instance.cfg"
      $DRY_RUN_CMD install -m 0644 ${mmcPackJson} "$INST/mmc-pack.json"
    fi

    $DRY_RUN_CMD mkdir -p "$MODS"
    $DRY_RUN_CMD ln -sf ${baritone} "$MODS/baritone.jar"

    SHADERPACKS="$INST/minecraft/shaderpacks"
    $DRY_RUN_CMD mkdir -p "$SHADERPACKS"
    $DRY_RUN_CMD ln -sf ${seus} "$SHADERPACKS/SEUS-Renewed-v1.0.1.zip"

    FORK_JAR=""
    if [ -d "$HOME/projects/meteor-client/build/libs" ]; then
      FORK_JAR=$(find "$HOME/projects/meteor-client/build/libs" -name "meteor-client-*.jar" | sort -V | tail -1)
    fi
    if [ -n "$FORK_JAR" ]; then
      $DRY_RUN_CMD ln -sf "$FORK_JAR" "$MODS/meteor-client.jar"
    else
      echo "Note: run ./gradlew build in ~/projects/meteor-client to install the mod" >&2
    fi
  '';
}
