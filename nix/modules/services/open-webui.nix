{ config, lib, pkgs, ... }:

let
  port = 6683;
  modelName = "mvr-assistant";
  baseModel = config.mandragora.ai.agentic.model;
  agentsMd = builtins.readFile ../../../AGENTS.md;
  systemPrompt = ''
    You are mvr-assistant, a personal assistant running locally on the Mandragora workstation.
    The document below is the canonical context for every AI agent on this system (Claude, Gemini, you).
    Use it as background for every reply: it tells you who the user is, what the system looks like, and what conventions to respect.

    -----8<----- AGENTS.md -----8<-----

  '' + agentsMd;
  modelfile = pkgs.writeText "${modelName}.Modelfile" ''
    FROM ${baseModel}
    SYSTEM """
    ${systemPrompt}
    """
  '';
in {
  services.open-webui = {
    enable = true;
    host = "0.0.0.0";
    inherit port;
    environment = {
      SCARF_NO_ANALYTICS = "True";
      DO_NOT_TRACK = "True";
      ANONYMIZED_TELEMETRY = "False";
      OLLAMA_BASE_URL = "http://127.0.0.1:11434";
      WEBUI_AUTH = "False";
      ENABLE_SIGNUP = "False";
      WEBUI_URL = "https://llama.mvr.ac";
      DEFAULT_MODELS = "${modelName}:latest";
    };
  };

  systemd.services.open-webui = {
    after = [ "ollama.service" "tailscaled.service" "ollama-create-mvr-assistant.service" ];
    wants = [ "ollama.service" "ollama-create-mvr-assistant.service" ];
  };

  systemd.services.ollama-create-mvr-assistant = {
    description = "Register ${modelName} Ollama model with AGENTS.md baked into SYSTEM prompt";
    after = [ "ollama.service" "network-online.target" ];
    requires = [ "ollama.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.ollama pkgs.curl ];
    script = ''
      for i in $(seq 1 60); do
        curl -fsS http://127.0.0.1:11434/api/version >/dev/null && break
        sleep 2
      done
      ollama create ${modelName} -f ${modelfile}
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "30min";
      Environment = [ "OLLAMA_HOST=127.0.0.1:11434" "HOME=/var/empty" ];
    };
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ port ];
}
