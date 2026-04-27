{ config, pkgs, lib, ... }:

let
  botPython = import ../../pkgs/bot-python.nix { inherit pkgs; };
  llmViaTelegramRoot = "/etc/nixos/mandragora/.local/share/llm-via-telegram";
  gpuLockRoot = "/etc/nixos/mandragora/.local/share/gpu-lock";
  llmViaTelegramState = "/home/m/.local/share/llm-via-telegram";
in
{
  systemd.tmpfiles.rules = [
    "d ${llmViaTelegramState} 0755 m users -"
    "d ${llmViaTelegramState}/data 0755 m users -"
    "d ${llmViaTelegramState}/logs 0755 m users -"
    "L+ /home/m/Projects/gpu-lock - - - - ${gpuLockRoot}"
  ];

  systemd.user.services.llm-via-telegram = {
    Unit = {
      Description = "LLM-via-Telegram bot (Ollama-backed gpt-oss:20b, GPU-coordinated)";
      After = [ "graphical-session.target" "network-online.target" ];
      Wants = [ "network-online.target" ];
      ConditionPathExists = [ "/dev/nvidia0" ];
    };
    Service = {
      Type = "simple";
      WorkingDirectory = llmViaTelegramState;
      ExecStart = "${botPython}/bin/python3 ${llmViaTelegramRoot}/main.py";
      EnvironmentFile = config.sops.secrets."llm_via_telegram/env".path;
      Environment = [
        "PATH=/run/current-system/sw/bin:/etc/profiles/per-user/m/bin:/nix/var/nix/profiles/default/bin"
        "PYTHONPATH=${gpuLockRoot}:${llmViaTelegramRoot}"
      ];
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
