{ pkgs, ... }:

let
  models = builtins.fromJSON (builtins.readFile ../../snippets/local-llm-models.json);

  roleParams = {
    agentic = {
      label = "agentic";
      contextWindow = 131072;
      maxTokens = 16384;
      attachments = false;
      reason = true;
    };
    gemma = {
      label = "chat";
      contextWindow = 131072;
      maxTokens = 16384;
      attachments = true;
      reason = true;
    };
    uncensored = {
      label = "uncensored";
      contextWindow = 131072;
      maxTokens = 16384;
      attachments = false;
      reason = true;
    };
    secondary = {
      label = "secondary";
      contextWindow = 40960;
      maxTokens = 8192;
      attachments = false;
      reason = true;
    };
    meme = {
      label = "vision";
      contextWindow = 128000;
      maxTokens = 8192;
      attachments = true;
      reason = false;
    };
  };

  mkModel = role: p: {
    id = models.${role};
    name = "${p.label} · ${models.${role}}";
    cost_per_1m_in = 0;
    cost_per_1m_out = 0;
    cost_per_1m_in_cached = 0;
    cost_per_1m_out_cached = 0;
    context_window = p.contextWindow;
    default_max_tokens = p.maxTokens;
    supports_attachments = p.attachments;
    can_reason = p.reason;
    options = { };
  };

  crushConfig = {
    "$schema" = "https://charm.land/crush.json";
    providers.ollama = {
      type = "openai-compat";
      name = "Ollama (local)";
      base_url = "http://127.0.0.1:11434/v1";
      api_key = "ollama";
      models = builtins.attrValues (builtins.mapAttrs mkModel roleParams);
    };
    models = {
      large = {
        model = models.agentic;
        provider = "ollama";
      };
      small = {
        model = models.agentic;
        provider = "ollama";
      };
    };
    options = {
      tui.transparent = true;
      context_paths = [
        "AGENTS.md"
        "CRUSH.md"
        "CLAUDE.md"
        ".cursorrules"
        "/etc/nixos/mandragora/AGENTS.md"
      ];
      initialize_as = "AGENTS.md";
    };
    permissions.allowed_tools = [
      "bash"
      "view"
      "ls"
      "grep"
      "edit"
      "write"
      "fetch"
      "sourcegraph"
      "glob"
      "multiedit"
      "todos"
      "download"
    ];
    tools = {
      ls = {
        max_depth = 0;
        max_items = 1000;
      };
      grep.timeout = 30;
    };
  };
in
{
  home.file.".config/crush/crush.json".source = pkgs.writeText "crush.json" (
    builtins.toJSON crushConfig
  );
}
