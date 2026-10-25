{ pkgs, lib, ... }:

let
  claudeFind = pkgs.writers.writePython3Bin "claude-find" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ../../snippets/claude-find.py);
  claudeReopen = pkgs.writeShellScriptBin "claude-reopen" (
    builtins.readFile ../../../.local/bin/claude-reopen.sh
  );
  retention = pkgs.writeShellApplication {
    name = "claude-transcript-retention";
    runtimeInputs = [ pkgs.jq ];
    text = builtins.readFile ../../../.local/bin/claude-transcript-retention.sh;
  };
in
{
  home.packages = [
    claudeFind
    claudeReopen
  ];

  home.activation.claudeTranscriptRetention = lib.hm.dag.entryAfter [
    "writeBoundary"
  ] "${retention}/bin/claude-transcript-retention";
}
