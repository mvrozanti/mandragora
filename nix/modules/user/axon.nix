{ config, lib, pkgs, ... }:
let
  # axon's `group_impact` reads ~/.axon/registry.json to enumerate sibling
  # repos and report cross-repo blast radius for a file path. The Mandragora
  # group lists every long-lived workspace likely to share imports / utilities
  # / typings with another — config repo + bot family + axon itself.
  #
  # registry.json is mutable at runtime (`axon` writes back to it after
  # index_paths invocations), so we cannot symlink it from /nix/store. We seed
  # it via a home-manager activation script: idempotent on missing, leaves
  # user mutations untouched on subsequent rebuilds.
  registry = {
    repos = [
      { name = "mandragora";          root = "/etc/nixos/mandragora";                              db_path = "/etc/nixos/mandragora/.axon/index.duckdb"; }
      { name = "axon";                root = "/home/m/Projects/axon";                              db_path = "/home/m/Projects/axon/.axon/index.duckdb"; }
      { name = "thought";             root = "/home/m/Projects/thought";                           db_path = "/home/m/Projects/thought/.axon/index.duckdb"; }
      { name = "im-gen";              root = "/home/m/Projects/im-gen";                            db_path = "/home/m/Projects/im-gen/.axon/index.duckdb"; }
      { name = "vtag";                root = "/etc/nixos/mandragora/.local/share/vtag";            db_path = "/etc/nixos/mandragora/.local/share/vtag/.axon/index.duckdb"; }
      { name = "gpu-lock";            root = "/etc/nixos/mandragora/.local/share/gpu-lock";        db_path = "/etc/nixos/mandragora/.local/share/gpu-lock/.axon/index.duckdb"; }
      { name = "llm-via-telegram";    root = "/etc/nixos/mandragora/.local/share/llm-via-telegram"; db_path = "/etc/nixos/mandragora/.local/share/llm-via-telegram/.axon/index.duckdb"; }
      { name = "stt-via-telegram";    root = "/etc/nixos/mandragora/.local/share/stt-via-telegram"; db_path = "/etc/nixos/mandragora/.local/share/stt-via-telegram/.axon/index.duckdb"; }
      { name = "ollama-context-proxy"; root = "/etc/nixos/mandragora/.local/share/ollama-context-proxy"; db_path = "/etc/nixos/mandragora/.local/share/ollama-context-proxy/.axon/index.duckdb"; }
      { name = "claude-web";          root = "/etc/nixos/mandragora/.local/share/claude-web";      db_path = "/etc/nixos/mandragora/.local/share/claude-web/.axon/index.duckdb"; }
      { name = "mandragora-audit";    root = "/etc/nixos/mandragora/.local/share/mandragora-audit"; db_path = "/etc/nixos/mandragora/.local/share/mandragora-audit/.axon/index.duckdb"; }
      { name = "meme-tagger";         root = "/etc/nixos/mandragora/.local/share/meme-tagger";    db_path = "/etc/nixos/mandragora/.local/share/meme-tagger/.axon/index.duckdb"; }
      { name = "rgb-control";         root = "/etc/nixos/mandragora/.local/share/rgb-control";    db_path = "/etc/nixos/mandragora/.local/share/rgb-control/.axon/index.duckdb"; }
    ];
    groups = {
      mandragora = [
        "mandragora" "axon" "thought" "im-gen"
        "vtag" "gpu-lock" "llm-via-telegram" "stt-via-telegram"
        "ollama-context-proxy" "claude-web" "mandragora-audit"
        "meme-tagger" "rgb-control"
      ];
      bots = [
        "vtag" "llm-via-telegram" "stt-via-telegram"
        "ollama-context-proxy" "meme-tagger"
      ];
    };
  };

  registrySeed = pkgs.writeText "axon-registry.json" (builtins.toJSON registry);
in
{
  home.activation.axonRegistrySeed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -e "$HOME/.axon/registry.json" ]; then
      $DRY_RUN_CMD mkdir -p "$HOME/.axon"
      $DRY_RUN_CMD install -m 644 ${registrySeed} "$HOME/.axon/registry.json"
    fi
  '';
}
