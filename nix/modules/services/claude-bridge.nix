{ pkgs, ... }:

let
  port = 4097;
  src = ../../../.local/share/claude-bridge/app.py;
  gpuLockRoot = ../../../.local/share/gpu-lock;
  models = builtins.fromJSON (builtins.readFile ../../snippets/local-llm-models.json);
  localModels = [
    {
      name = "cc-qwen3.6";
      from = models.coder;
      num_ctx = 65536;
    }
    {
      name = "cc-gptoss";
      from = models.agentic;
      num_ctx = 65536;
    }
  ];
  pyEnv = pkgs.python3.withPackages (ps: [
    ps.aiohttp
    ps.claude-agent-sdk
    ps.httpx
  ]);
in
{
  mandragora.hub.services.claude-bridge = {
    inherit port;
    userService = true;
    memoryMax = "10G";
    systemd = {
      description = "claude-bridge — Claude Code sessions (Claude, DeepSeek or a local Ollama model) over the HTTP and event API the phone speaks";
      wantedBy = [ "default.target" ];
      restartTriggers = [ (builtins.readFile src) ];
      path = [
        pkgs.claude-code
        pkgs.poppler-utils
        "/run/wrappers"
        "/home/m/.nix-profile"
        "/etc/profiles/per-user/m"
        "/nix/var/nix/profiles/default"
        "/run/current-system/sw"
      ];
      environment = {
        CLAUDE_BRIDGE_HOST = "0.0.0.0";
        CLAUDE_BRIDGE_PORT = toString port;
        CLAUDE_BRIDGE_PASSWORD_FILE = "/home/m/.local/state/claude-bridge/server-password";
        CLAUDE_BRIDGE_DEEPSEEK_KEY = "/run/secrets/deepseek/api_key";
        CLAUDE_BRIDGE_CLI = "${pkgs.claude-code}/bin/claude";
        CLAUDE_BRIDGE_LOCAL_MODELS = builtins.toJSON localModels;
        PYTHONPATH = "${gpuLockRoot}";
      };
      serviceConfig = {
        Type = "simple";
        WorkingDirectory = "/home/m";
        ExecStart = "${pyEnv}/bin/python ${src}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
      unitConfig.ConditionPathExists = "/run/secrets/deepseek/api_key";
    };
  };
}
