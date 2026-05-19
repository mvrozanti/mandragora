{ pkgs, lib, ... }:

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
      pkgs.statix
      pkgs.deadnix
    ]}:$PATH
    exec ${pkgs.bash}/bin/bash "$AUDIT_HOME/audit.sh" "$@"
  '';
in
{
  environment.systemPackages = [ mandragora-audit ];

  system.activationScripts.mandragoraGitHooks = {
    text = builtins.replaceStrings
      [ "@auditTree@" "@sed@" "@grep@" ]
      [ "${auditTree}" "${pkgs.gnused}/bin/sed" "${pkgs.gnugrep}/bin/grep" ]
      (builtins.readFile ./setup-git-hooks.sh);
    deps = [ ];
  };
}
