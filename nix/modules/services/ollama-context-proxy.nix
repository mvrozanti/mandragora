{ config, lib, pkgs, ... }:

let
  port = 11435;
  src = "/persistent/mandragora/.local/share/ollama-context-proxy/proxy.py";
  pyEnv = pkgs.python3.withPackages (ps: [ ps.aiohttp ]);
  systemPromptFile = pkgs.writeText "mvr-system-prompt.txt" (builtins.readFile ../../../AGENTS.md);
in {
  systemd.services.ollama-context-proxy = {
    description = "Reverse proxy in front of Ollama that injects AGENTS.md as a default system message";
    after = [ "ollama.service" ];
    wants = [ "ollama.service" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      OLLAMA_UPSTREAM = "http://127.0.0.1:11434";
      LISTEN_HOST = "127.0.0.1";
      LISTEN_PORT = toString port;
      MVR_SYSTEM_PROMPT_FILE = "${systemPromptFile}";
    };
    restartTriggers = [ (builtins.readFile ../../../.local/share/ollama-context-proxy/proxy.py) ];
    serviceConfig = {
      ExecStart = "${pyEnv}/bin/python ${src}";
      Restart = "on-failure";
      RestartSec = "5s";
      DynamicUser = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };
}
