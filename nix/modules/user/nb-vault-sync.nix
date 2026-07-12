{ pkgs, ... }:

let
  nbVaultSync = pkgs.writers.writePython3Bin "nb-vault-sync" {
    libraries = [ pkgs.python3Packages.requests ];
    flakeIgnore = [
      "E501"
      "E402"
    ];
  } (builtins.readFile ../../snippets/nb-vault-sync.py);
in
{
  home.packages = [ nbVaultSync ];
}
