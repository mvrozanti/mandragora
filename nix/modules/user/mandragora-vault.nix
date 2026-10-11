{ pkgs, ... }:

let
  secretPatterns = ../../../.local/share/mandragora-audit/lib/secret-patterns.txt;

  mandragoraVault =
    pkgs.writers.writePython3Bin "mandragora-vault"
      {
        flakeIgnore = [
          "E501"
          "W503"
          "W504"
        ];
      }
      (
        builtins.replaceStrings [ "@secretPatterns@" ] [ "${secretPatterns}" ] (
          builtins.readFile ../../../.local/bin/mandragora-vault.py
        )
      );

  vaultHooks = pkgs.writeShellScriptBin "pre-commit" "exec ${mandragoraVault}/bin/mandragora-vault check --staged";
in
{
  home.packages = [ mandragoraVault ];

  programs.git.includes = [
    {
      condition = "gitdir:~/Documents/mandragora-desktop-obsidian-vault/";
      contents.core.hooksPath = "${vaultHooks}/bin";
    }
  ];
}
