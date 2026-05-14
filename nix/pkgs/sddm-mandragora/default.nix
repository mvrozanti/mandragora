{ runCommand, sddm-astronaut }:
runCommand "sddm-mandragora-theme"
  {
    propagatedBuildInputs = sddm-astronaut.propagatedBuildInputs;
  }
  ''
    src=${sddm-astronaut}/share/sddm/themes/sddm-astronaut-theme
    dst=$out/share/sddm/themes/sddm-mandragora
    mkdir -p $(dirname "$dst")
    cp -r "$src" "$dst"
    chmod -R u+w "$dst"
    install -m 0644 ${./../../etc/sddm/mandragora.conf} "$dst/Themes/mandragora.conf"
    sed -i \
      -e 's|^Name=.*|Name=sddm-mandragora|' \
      -e 's|^Theme-Id=.*|Theme-Id=sddm-mandragora|' \
      -e 's|^ConfigFile=.*|ConfigFile=Themes/mandragora.conf|' \
      "$dst/metadata.desktop"
  ''
