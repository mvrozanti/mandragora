{ config, pkgs, ... }:

let
  guard = pkgs.writeShellApplication {
    name = "nixos-rebuild";
    runtimeInputs = [
      pkgs.git
      pkgs.coreutils
      pkgs.gnused
      pkgs.util-linux
    ];
    runtimeEnv = {
      REAL_NIXOS_REBUILD = "${config.system.build.nixos-rebuild}/bin/nixos-rebuild";
      MANDRAGORA_REPO_DIR = "/etc/nixos/mandragora";
    };
    text = builtins.readFile ../../../.local/bin/nixos-rebuild-guard.sh;
  };
in
{
  system.tools.nixos-rebuild.enable = false;
  environment.systemPackages = [ guard ];
}
