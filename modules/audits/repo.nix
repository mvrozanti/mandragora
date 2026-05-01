{ config, pkgs, lib, ... }:

let
  auditTree = pkgs.runCommand "mandragora-audit-tree" { } ''
    cp -r ${../../.local/share/mandragora-audit} $out
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
      if [ -d /etc/nixos/mandragora/.git ]; then
        ${pkgs.git}/bin/git -C /etc/nixos/mandragora config --local \
          core.hooksPath ${auditTree}/hooks || true
      fi
    '';
    deps = [ ];
  };
}
