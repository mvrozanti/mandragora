{ pkgs, ... }:

let
  port = 6689;
  src = ../../hosts/mandragora-phone/ask/server.py;
  gpuLockRoot = ../../../.local/share/gpu-lock;
  models = builtins.fromJSON (builtins.readFile ../../snippets/local-llm-models.json);
  pyEnv = import ../../pkgs/ask-python.nix { inherit pkgs; };
in
{
  mandragora.hub.services.phone-ask = {
    inherit port;
    userService = true;
    systemd = {
      description = "phone-ask — the local model and the desktop's shell for the phone's ask screen, over the tailnet";
      wantedBy = [ "default.target" ];
      restartTriggers = [ (builtins.readFile src) ];
      path = [
        "/etc/profiles/per-user/m"
        "/nix/var/nix/profiles/default"
        "/run/current-system/sw"
      ];
      environment = {
        PHONE_ASK_HOST = "0.0.0.0";
        PHONE_ASK_PORT = toString port;
        PHONE_ASK_STATE = "/home/m/.local/state/phone-ask";
        PHONE_ASK_AGENTS_MD = "${../../../AGENTS.md}";
        PHONE_ASK_LOCAL_LLM_MD = "${../../../docs/local-llm.md}";
        OLLAMA_MODEL = models.agentic;
        PYTHONPATH = "${gpuLockRoot}";
        MANDRAGORA_AGENT = "phone-ask";
      };
      serviceConfig = {
        Type = "simple";
        WorkingDirectory = "/home/m";
        ExecStart = "${pyEnv}/bin/python ${src}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
