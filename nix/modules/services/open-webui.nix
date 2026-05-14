{ config, lib, pkgs, ... }:

let
  port = 6683;
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
    };
  };

  systemd.services.open-webui = {
    after = [ "ollama.service" "tailscaled.service" ];
    wants = [ "ollama.service" ];
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ port ];
}
