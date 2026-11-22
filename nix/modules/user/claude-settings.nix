{ pkgs, lib, ... }:

let
  merge = pkgs.writeShellApplication {
    name = "claude-settings-merge";
    runtimeInputs = [ pkgs.jq ];
    text = builtins.readFile ../../../.local/bin/claude-settings-merge.sh;
  };
in
{
  home.activation.claudeDeclaredSettings = lib.hm.dag.entryAfter [
    "writeBoundary"
  ] "${merge}/bin/claude-settings-merge ${../../../.claude/settings.json}";
}
