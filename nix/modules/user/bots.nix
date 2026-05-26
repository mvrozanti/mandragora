{ config, osConfig, pkgs, lib, ... }:

let
  botPython = import ../../pkgs/bot-python.nix { inherit pkgs; };
  llmViaTelegramRoot = "/etc/nixos/mandragora/.local/share/llm-via-telegram";
  gpuLockRoot = "/etc/nixos/mandragora/.local/share/gpu-lock";
  llmViaTelegramState = "/home/m/.local/share/llm-via-telegram";
  sttViaTelegramRoot = "/etc/nixos/mandragora/.local/share/stt-via-telegram";
  sttViaTelegramState = "/home/m/.local/share/stt-via-telegram";
  sttCoreRoot = "/etc/nixos/mandragora/.local/share/stt-core";
  sttCoreState = "/home/m/.local/share/stt-core";
  ttsCloneCoreRoot = "/etc/nixos/mandragora/.local/share/tts-clone-core";
  ttsCloneCoreState = "/home/m/.local/share/tts-clone-core";
  vtagState = "/home/m/.local/share/vtag";
in
{
  home.activation.botsState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p ${llmViaTelegramState}/data ${llmViaTelegramState}/logs
    mkdir -p ${sttViaTelegramState}/data ${sttViaTelegramState}/logs ${sttViaTelegramState}/hf-cache
    mkdir -p ${sttCoreState}/data ${sttCoreState}/logs ${sttCoreState}/hf-cache
    mkdir -p ${ttsCloneCoreState}/refs ${ttsCloneCoreState}/out ${ttsCloneCoreState}/hf-cache
    mkdir -p ${vtagState}/logs
    if [ -e /home/m/Projects/gpu-lock ] && [ ! -L /home/m/Projects/gpu-lock ]; then
      rm -rf /home/m/Projects/gpu-lock
    fi
    ln -sfn ${gpuLockRoot} /home/m/Projects/gpu-lock
  '';

  systemd.user.services.im-gen-bot = {
    Unit = {
      Description = "im-gen Telegram bot (Flux on RTX 5070 Ti)";
      After = [ "graphical-session.target" "network-online.target" "im-gen-cipher.service" ];
      Wants = [ "network-online.target" ];
      Requires = [ "im-gen-cipher.service" ];
      ConditionPathExists = [
        "/dev/nvidia0"
        "/home/m/Projects/im-gen/invokeai-venv/bin/python"
        "/home/m/Projects/im-gen/bot.sh"
      ];
    };
    Service = {
      Type = "simple";
      WorkingDirectory = "/home/m/Projects/im-gen";
      ExecStart = "/home/m/Projects/im-gen/bot.sh";
      Environment = "PATH=/run/current-system/sw/bin:/etc/profiles/per-user/m/bin:/nix/var/nix/profiles/default/bin";
      Restart = "on-failure";
      RestartSec = 10;
      TimeoutStartSec = "5min";
      Slice = "im-gen.slice";
      MemoryMax = "22G";
      MemorySwapMax = "0";
      OOMScoreAdjust = 1000;
      OOMPolicy = "kill";
      TasksMax = 4096;
      ManagedOOMSwap = "kill";
      ManagedOOMMemoryPressure = "kill";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.services.stt-via-telegram = {
    Unit = {
      Description = "STT-via-Telegram bot (faster-whisper large-v3 on RTX 5070 Ti, EN/PT)";
      After = [ "graphical-session.target" "network-online.target" ];
      Wants = [ "network-online.target" ];
      ConditionPathExists = [
        "/dev/nvidia0"
        "${sttViaTelegramRoot}/bot.sh"
      ];
    };
    Service = {
      Type = "simple";
      WorkingDirectory = sttViaTelegramRoot;
      ExecStart = "${sttViaTelegramRoot}/bot.sh";
      EnvironmentFile = osConfig.sops.secrets."stt_via_telegram/env".path;
      Environment = [
        "PATH=/run/current-system/sw/bin:/etc/profiles/per-user/m/bin:/nix/var/nix/profiles/default/bin"
        "STT_VIA_TELEGRAM_STATE_DIR=${sttViaTelegramState}"
        "STT_VIA_TELEGRAM_DATA_DIR=${sttViaTelegramState}/data"
      ];
      Restart = "on-failure";
      RestartSec = 10;
      TimeoutStartSec = "10min";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.services.stt-core = {
    Unit = {
      Description = "STT core service (faster-whisper FastAPI, EN/PT, tailnet-bound)";
      After = [ "graphical-session.target" "network-online.target" ];
      Wants = [ "network-online.target" ];
      ConditionPathExists = [
        "/dev/nvidia0"
        "${sttCoreRoot}/bot.sh"
      ];
    };
    Service = {
      Type = "simple";
      WorkingDirectory = sttCoreRoot;
      ExecStart = "${sttCoreRoot}/bot.sh";
      Environment = [
        "PATH=/run/current-system/sw/bin:/etc/profiles/per-user/m/bin:/nix/var/nix/profiles/default/bin"
        "STT_CORE_STATE_DIR=${sttCoreState}"
        "STT_CORE_DATA_DIR=${sttCoreState}/data"
        "STT_CORE_BIND_HOST=0.0.0.0"
        "STT_CORE_BIND_PORT=8091"
      ];
      Restart = "on-failure";
      RestartSec = 10;
      TimeoutStartSec = "10min";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.services.tts-clone-core = {
    Unit = {
      Description = "TTS voice-imitation core service (F5-TTS on RTX 5070 Ti, tailnet-bound)";
      After = [ "graphical-session.target" "network-online.target" ];
      Wants = [ "network-online.target" ];
      ConditionPathExists = [
        "/dev/nvidia0"
        "${ttsCloneCoreRoot}/bot.sh"
      ];
    };
    Service = {
      Type = "simple";
      WorkingDirectory = ttsCloneCoreRoot;
      ExecStart = "${ttsCloneCoreRoot}/bot.sh";
      Environment = [
        "PATH=/run/current-system/sw/bin:/etc/profiles/per-user/m/bin:/nix/var/nix/profiles/default/bin"
        "TTS_CLONE_STATE_DIR=${ttsCloneCoreState}"
        "TTS_CLONE_BIND_HOST=0.0.0.0"
        "TTS_CLONE_BIND_PORT=8092"
      ];
      Restart = "on-failure";
      RestartSec = 10;
      TimeoutStartSec = "15min";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.services.llm-via-telegram = {
    Unit = {
      Description = "LLM-via-Telegram bot (Ollama-backed local model, GPU-coordinated)";
      After = [ "graphical-session.target" "network-online.target" ];
      Wants = [ "network-online.target" ];
      ConditionPathExists = [ "/dev/nvidia0" ];
    };
    Service = {
      Type = "simple";
      WorkingDirectory = llmViaTelegramState;
      ExecStart = "${botPython}/bin/python3 ${llmViaTelegramRoot}/main.py";
      EnvironmentFile = osConfig.sops.secrets."llm_via_telegram/env".path;
      Environment = [
        "PATH=/run/current-system/sw/bin:/etc/profiles/per-user/m/bin:/nix/var/nix/profiles/default/bin"
        "PYTHONPATH=${gpuLockRoot}:${llmViaTelegramRoot}"
        "LLM_VIA_TELEGRAM_DATA_DIR=${llmViaTelegramState}/data"
        "LLM_VIA_TELEGRAM_LOG_DIR=${llmViaTelegramState}/logs"
      ];
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

}
