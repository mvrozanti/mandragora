{ pkgs, ... }:

let
  claudeFind = pkgs.writers.writePython3Bin "claude-find" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ../../snippets/claude-find.py);
  claudeReopen = pkgs.writeShellScriptBin "claude-reopen" (
    builtins.readFile ../../../.local/bin/claude-reopen.sh
  );
in
{
  home.packages = [
    claudeFind
    claudeReopen
  ];
}
