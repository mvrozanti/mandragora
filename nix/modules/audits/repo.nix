{ config, pkgs, lib, ... }:

let
  auditTree = pkgs.runCommand "mandragora-audit-tree" { } ''
    cp -r ${../../../.local/share/mandragora-audit} $out
    chmod -R +w $out
    chmod +x $out/audit.sh $out/checks/*.sh $out/hooks/*
  '';

  mandragora-audit = pkgs.writeShellScriptBin "mandragora-audit" ''
    export AUDIT_HOME="${auditTree}"
    export PATH=${lib.makeBinPath [
      pkgs.git
      pkgs.ripgrep
      pkgs.gnugrep
      pkgs.coreutils
      pkgs.findutils
      pkgs.gawk
      pkgs.bash
    ]}:$PATH
    exec ${pkgs.bash}/bin/bash "$AUDIT_HOME/audit.sh" "$@"
  '';
in
{
  environment.systemPackages = [ mandragora-audit ];

  system.activationScripts.mandragoraGitHooks = {
    text = ''
      cfg=/etc/nixos/mandragora/.git/config
      if [ -f "$cfg" ]; then
        target="${auditTree}/hooks"
        current=$(${pkgs.gnused}/bin/sed -n 's/^[[:space:]]*hooksPath[[:space:]]*=[[:space:]]*//p' "$cfg" | head -n1)
        if [ "$current" != "$target" ]; then
          ${pkgs.gnused}/bin/sed -i '/^\[core\]/,/^\[/ { /hooksPath[[:space:]]*=/d }' "$cfg"
          if ${pkgs.gnugrep}/bin/grep -q '^\[core\]' "$cfg"; then
            ${pkgs.gnused}/bin/sed -i "/^\[core\]/a\\	hooksPath = $target" "$cfg"
          else
            printf '\n[core]\n\thooksPath = %s\n' "$target" >> "$cfg"
          fi
        fi
      fi
    '';
    deps = [ ];
  };
}
