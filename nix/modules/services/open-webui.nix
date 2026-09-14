_:

let
  port = 6683;
  models = builtins.fromJSON (builtins.readFile ../../snippets/local-llm-models.json);
in
{
  services.open-webui = {
    enable = true;
    host = "0.0.0.0";
    inherit port;
    environment = {
      SCARF_NO_ANALYTICS = "True";
      DO_NOT_TRACK = "True";
      ANONYMIZED_TELEMETRY = "False";
      OLLAMA_BASE_URL = "http://127.0.0.1:11435";
      WEBUI_AUTH = "False";
      ENABLE_SIGNUP = "False";
      WEBUI_URL = "https://chat.mvr.ac";
      ENABLE_PERSISTENT_CONFIG = "False";
      DEFAULT_MODELS = models.gemma;
    };
  };

  systemd.services.open-webui = {
    after = [
      "ollama.service"
      "ollama-context-proxy.service"
      "tailscaled.service"
    ];
    wants = [
      "ollama.service"
      "ollama-context-proxy.service"
    ];
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ port ];
}
