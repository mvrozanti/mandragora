{
  pkgs,
  lib,
  ...
}:

let
  tailnet = builtins.fromJSON (builtins.readFile ../../snippets/tailnet.json);
  gpuLockRoot = "/etc/nixos/mandragora/.local/share/gpu-lock";
  sttCoreRoot = "/home/m/Projects/stt-core";
  sttCoreState = "/home/m/.local/share/stt-core";
  ttsCloneCoreRoot = "/home/m/Projects/tts-clone-core";
  ttsCloneCoreState = "/home/m/.local/share/tts-clone-core";
  memeState = "/home/m/.local/share/meme";
  axonRoot = ../../../.local/share/axon;
  axonState = "/home/m/.local/share/axon";
  axonRepo = "/home/m/Projects/axon";
  axonWebRoot = ../../../.local/share/axon-web;
  axonWebState = "/home/m/.local/share/axon-web";
  axonWebRepo = "/home/m/Projects/axon-web";
in
{
  home.activation.botsState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p ${sttCoreState}/data ${sttCoreState}/logs ${sttCoreState}/hf-cache
    mkdir -p ${ttsCloneCoreState}/refs ${ttsCloneCoreState}/out ${ttsCloneCoreState}/hf-cache
    mkdir -p ${memeState}/logs
    mkdir -p ${axonState}/logs
    mkdir -p ${axonWebState}/logs
    if [ -e /home/m/Projects/gpu-lock ] && [ ! -L /home/m/Projects/gpu-lock ]; then
      rm -rf /home/m/Projects/gpu-lock
    fi
    ln -sfn ${gpuLockRoot} /home/m/Projects/gpu-lock
  '';

  systemd.user.services.stt-core = {
    Unit = {
      Description = "STT core service (faster-whisper FastAPI, EN/PT, tailnet-bound)";
      After = [
        "graphical-session.target"
        "network-online.target"
      ];
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
      MemoryMax = "6G";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.services.axon = {
    Unit = {
      Description = "Axon HTTP API (loopback, multi-repo aggregate; consumed by axon-web)";
      After = [
        "graphical-session.target"
        "network-online.target"
      ];
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
      MemoryMax = "1G";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.services.axon-web = {
    Unit = {
      Description = "Axon SPA + thin Node runtime (tailnet-bound; proxies /api/* to axon)";
      After = [
        "graphical-session.target"
        "network-online.target"
        "axon.service"
      ];
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
      MemoryMax = "1G";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.services.tts-clone-core = {
    Unit = {
      Description = "TTS voice-imitation core service (F5-TTS on RTX 5070 Ti, tailnet-bound)";
      After = [
        "graphical-session.target"
        "network-online.target"
      ];
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
      MemoryMax = "6G";
      RuntimeMaxSec = "12h";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
