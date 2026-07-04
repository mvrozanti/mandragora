{ pkgs, ... }:

let
  vulnPublish = pkgs.writeShellApplication {
    name = "vuln-publish";
    runtimeInputs = [
      pkgs.jq
      pkgs.rsync
      pkgs.openssh
      pkgs.coreutils
      pkgs.gnused
      pkgs.inetutils
    ];
    text = builtins.readFile ../../../.local/bin/vuln-publish.sh;
  };
in
{
  environment.systemPackages = [ vulnPublish ];
}
