{ pkgs }:

let
  env = import ./env.nix { inherit pkgs; };

  defaultProject = "/home/m/Projects/mandragora-world";

  launcher = pkgs.writeShellApplication {
    name = "ue5";
    runtimeInputs = with pkgs; [ coreutils ] ++ env.scripts ++ [ env.fhs ];
    text = ''
      proj="''${1:-}"
      if [ -z "$proj" ]; then
        cur="$PWD"
        while [ "$cur" != "/" ]; do
          if compgen -G "$cur/*.uproject" > /dev/null 2>&1; then
            proj="$cur"
            break
          fi
          cur="$(dirname "$cur")"
        done
      fi
      if [ -z "$proj" ] || [ ! -d "$proj" ]; then
        proj=${defaultProject}
      fi
      cd "$proj"
      export PROJECT_ROOT="$proj"
      exec gpu-lock run --name ue5-editor --expect 3600 -- \
        ue5-fhs -c ue5-editor
    '';
  };
in
pkgs.runCommand "ue5-launcher" { } ''
  mkdir -p $out/bin $out/share/applications
  ln -s ${launcher}/bin/ue5 $out/bin/ue5
  for s in ${pkgs.lib.concatStringsSep " " (map (p: "${p}/bin/*") env.scripts)}; do
    ln -s "$s" "$out/bin/$(basename "$s")"
  done
  ln -s ${env.fhs}/bin/ue5-fhs $out/bin/ue5-fhs
  cat > $out/share/applications/ue5.desktop <<EOF
  [Desktop Entry]
  Type=Application
  Name=Unreal Editor
  GenericName=Game Editor
  Comment=Launch UE5 editor on the nearest *.uproject (fallback: Mandragora World)
  Exec=${launcher}/bin/ue5
  Icon=applications-games
  Terminal=false
  Categories=Development;Game;
  StartupNotify=true
  EOF
''
