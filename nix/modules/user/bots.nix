{ osConfig, pkgs, lib, ... }:

let
  tailnet = builtins.fromJSON (builtins.readFile ../../snippets/tailnet.json);
  botPython = import ../../pkgs/bot-python.nix { inherit pkgs; };
  teacherPython = import ../../pkgs/teacher-python.nix { inherit pkgs; };
  llmViaTelegramRoot = "/home/m/Projects/llm-via-telegram";
  gpuLockRoot = "/etc/nixos/mandragora/.local/share/gpu-lock";
  llmViaTelegramState = "/home/m/.local/share/llm-via-telegram";
  sttViaTelegramRoot = "/home/m/Projects/stt-via-telegram";
  sttViaTelegramState = "/home/m/.local/share/stt-via-telegram";
  sttCoreRoot = "/home/m/Projects/stt-core";
  sttCoreState = "/home/m/.local/share/stt-core";
  ttsCloneCoreRoot = "/home/m/Projects/tts-clone-core";
  ttsCloneCoreState = "/home/m/.local/share/tts-clone-core";
  teacherRoot = "/home/m/Projects/teacher";
  teacherState = "/home/m/.local/share/teacher";
  vtagState = "/home/m/.local/share/vtag";
  axonRoot = "/etc/nixos/mandragora/.local/share/axon";
  axonState = "/home/m/.local/share/axon";
  axonRepo = "/home/m/Projects/axon";
  axonWebRoot = "/etc/nixos/mandragora/.local/share/axon-web";
  axonWebState = "/home/m/.local/share/axon-web";
  axonWebRepo = "/home/m/Projects/axon-web";
  intPython = import ../../pkgs/int-python.nix { inherit pkgs; };
  intRoot = "/home/m/Projects/4chan-international-visualizer";
  intState = "/home/m/.local/share/4chan-int";
in
{
  home.activation.botsState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p ${llmViaTelegramState}/data ${llmViaTelegramState}/logs
    mkdir -p ${sttViaTelegramState}/data ${sttViaTelegramState}/logs ${sttViaTelegramState}/hf-cache
    mkdir -p ${sttCoreState}/data ${sttCoreState}/logs ${sttCoreState}/hf-cache
    mkdir -p ${ttsCloneCoreState}/refs ${ttsCloneCoreState}/out ${ttsCloneCoreState}/hf-cache
    mkdir -p ${teacherState}/data ${teacherState}/logs
    [ -f ${teacherState}/.env ] || install -m 0600 /dev/null ${teacherState}/.env
    mkdir -p ${vtagState}/logs
    mkdir -p ${axonState}/logs
    mkdir -p ${axonWebState}/logs
    mkdir -p ${intState}/hf-cache
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
      Environment = [
        "PATH=/run/current-system/sw/bin:/etc/profiles/per-user/m/bin:/nix/var/nix/profiles/default/bin"
        "TORCHINDUCTOR_COMPILE_THREADS=4"
      ];
      Restart = "on-failure";
      RestartSec = 10;
      TimeoutStartSec = "5min";
      Slice = "im-gen.slice";
      MemoryMax = "18G";
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

  systemd.user.services.axon = {
    Unit = {
      Description = "Axon HTTP API (loopback, multi-repo aggregate; consumed by axon-web)";
      After = [ "graphical-session.target" "network-online.target" ];
      Wants = [ "network-online.target" ];
      ConditionPathExists = [
        "${axonRoot}/bot.sh"
      ];
    };
    Service = {
      Type = "simple";
      WorkingDirectory = axonRepo;
      ExecStart = "${axonRoot}/bot.sh";
      Environment = [
        "PATH=${pkgs.axon}/bin:/run/current-system/sw/bin:/etc/profiles/per-user/m/bin:/nix/var/nix/profiles/default/bin:/home/m/.local/bin"
        "AXON_STATE_DIR=${axonState}"
        "AXON_BIND_HOST=${tailnet.desktop.ip}"
        "AXON_BIND_PORT=7070"
      ];
      Restart = "on-failure";
      RestartSec = 10;
      TimeoutStartSec = "2min";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.services.axon-web = {
    Unit = {
      Description = "Axon SPA + thin Node runtime (tailnet-bound; proxies /api/* to axon)";
      After = [ "graphical-session.target" "network-online.target" "axon.service" ];
      Wants = [ "network-online.target" ];
      ConditionPathExists = [
        "${axonWebRoot}/bot.sh"
        "${axonWebRepo}/server.mjs"
        "${axonWebRepo}/dist/index.html"
      ];
    };
    Service = {
      Type = "simple";
      WorkingDirectory = axonWebRepo;
      ExecStart = "${axonWebRoot}/bot.sh";
      Environment = [
        "PATH=/run/current-system/sw/bin:/etc/profiles/per-user/m/bin:/nix/var/nix/profiles/default/bin:/home/m/.local/bin"
        "AXON_WEB_STATE_DIR=${axonWebState}"
        "AXON_WEB_HOST=${tailnet.desktop.ip}"
        "AXON_WEB_PORT=8081"
        "AXON_UPSTREAM=http://127.0.0.1:7070"
        "AXON_WEB_ROOT=${axonWebRepo}/dist"
      ];
      Restart = "on-failure";
      RestartSec = 10;
      TimeoutStartSec = "2min";
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
        "MAX_GEN_CHARS=5000"
      ];
      Restart = "on-failure";
      RestartSec = 10;
      TimeoutStartSec = "15min";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.services.teacher-teach = {
    Unit = {
      Description = "Teacher — Socratic Telegram tutor (Claude API)";
      After = [ "graphical-session.target" "network-online.target" ];
      Wants = [ "network-online.target" ];
      ConditionPathExists = [
        "${teacherRoot}/teacher/main.py"
        "${teacherRoot}/AGENTS.md"
      ];
    };
    Service = {
      Type = "simple";
      WorkingDirectory = teacherRoot;
      ExecStart = "${teacherPython}/bin/python -m teacher.main";
      EnvironmentFile = [
        osConfig.sops.templates."teacher_teach/env".path
        "-${teacherState}/.env"
      ];
      Environment = [
        "PATH=/run/current-system/sw/bin:/etc/profiles/per-user/m/bin:/nix/var/nix/profiles/default/bin"
        "PYTHONPATH=${teacherRoot}"
        "TEACHER_DB_PATH=${teacherState}/data/teacher.db"
        "TEACHER_BOOKS_DIR=/home/m/Documents/library/books"
        "TEACHER_AGENTS_MD=${teacherRoot}/AGENTS.md"
        "TEACHER_READ_ROOTS=/home/m/Documents,/home/m/Projects,/etc/nixos/mandragora"
      ];
      Restart = "on-failure";
      RestartSec = 10;
      TimeoutStartSec = "2min";
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

  systemd.user.services.int-scraper = {
    Unit = {
      Description = "4chan /int/ scraper (CPU, always-on; country reply graph + enrichment queue)";
      After = [ "graphical-session.target" "network-online.target" ];
      Wants = [ "network-online.target" ];
      ConditionPathExists = [ "${intRoot}/backend/scraper.py" ];
    };
    Service = {
      Type = "simple";
      WorkingDirectory = "${intRoot}/backend";
      ExecStart = "${intPython}/bin/python ${intRoot}/backend/scraper.py";
      Environment = [
        "PATH=/run/current-system/sw/bin:/etc/profiles/per-user/m/bin:/nix/var/nix/profiles/default/bin"
        "INT_DB=${intState}/int.db"
        "INT_BOARDS=int,pol"
      ];
      Restart = "always";
      RestartSec = 10;
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.services.int-api = {
    Unit = {
      Description = "4chan /int/ read API (Flask, tailnet-bound; consumed by 4chan.mvr.ac)";
      After = [ "graphical-session.target" "network-online.target" ];
      Wants = [ "network-online.target" ];
      ConditionPathExists = [ "${intRoot}/backend/api.py" ];
    };
    Service = {
      Type = "simple";
      WorkingDirectory = "${intRoot}/backend";
      ExecStart = "${intPython}/bin/python ${intRoot}/backend/api.py";
      Environment = [
        "PATH=/run/current-system/sw/bin:/etc/profiles/per-user/m/bin:/nix/var/nix/profiles/default/bin"
        "INT_DB=${intState}/int.db"
        "INT_BOARDS=int,pol"
        "INT_API_HOST=${tailnet.desktop.ip}"
        "INT_API_PORT=2718"
      ];
      Restart = "always";
      RestartSec = 10;
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.services.int-enrich = {
    Unit = {
      Description = "4chan /int/ enrichment drain (GPU via gpu-lock; topics + emotions, deferred when GPU busy)";
      After = [ "graphical-session.target" "network-online.target" ];
      Wants = [ "network-online.target" ];
      ConditionPathExists = [
        "/dev/nvidia0"
        "${intRoot}/backend/run-enrich.sh"
      ];
    };
    Service = {
      Type = "oneshot";
      WorkingDirectory = "${intRoot}/backend";
      ExecStart = "${intRoot}/backend/run-enrich.sh";
      Environment = [
        "PATH=/run/current-system/sw/bin:/etc/profiles/per-user/m/bin:/nix/var/nix/profiles/default/bin"
        "LD_LIBRARY_PATH=/run/current-system/sw/share/nix-ld/lib"
        "INT_DB=${intState}/int.db"
        "INT_VENV=${intRoot}/backend/.venv"
        "HF_HOME=${intState}/hf-cache"
      ];
      TimeoutStartSec = "30min";
      MemoryMax = "14G";
      MemorySwapMax = "0";
      OOMScoreAdjust = 1000;
      OOMPolicy = "kill";
      ManagedOOMSwap = "kill";
      ManagedOOMMemoryPressure = "kill";
    };
  };

  systemd.user.timers.int-enrich = {
    Unit = {
      Description = "Periodic 4chan /int/ enrichment drain";
    };
    Timer = {
      OnBootSec = "5min";
      OnUnitInactiveSec = "2min";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };

}
