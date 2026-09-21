{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.mandragora.voiceRvc;
  project = "/home/m/Projects/voice-convert-core";
  rvcDir = "${project}/rvc";
  venvPy = "${project}/.venv-train/bin/python";
  gpuLock = pkgs.callPackage ../../pkgs/gpu-lock.nix { };

  launcher = pkgs.writeShellScript "voice-rvc-launch" ''
    set -euo pipefail

    VENV_PY=${venvPy}
    if [ ! -x "$VENV_PY" ]; then
      echo "voice-rvc: ${project}/.venv-train missing — run train-bootstrap.sh first" >&2
      exit 1
    fi

    cd ${rvcDir}

    PY_LIB_DIR=$(echo "${project}/.venv-train"/lib/python*/site-packages | awk '{print $1}')
    NVIDIA_LIBS=""
    for d in "$PY_LIB_DIR"/nvidia/*/lib; do
      [ -d "$d" ] && NVIDIA_LIBS="$NVIDIA_LIBS:$d"
    done
    export LD_LIBRARY_PATH="/run/opengl-driver/lib$NVIDIA_LIBS:${pkgs.portaudio}/lib:${pkgs.alsa-lib}/lib:${pkgs.pipewire}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export TRITON_LIBCUDA_PATH="/run/opengl-driver/lib"

    RVC_MODEL="''${RVC_MODEL:-}"
    if [ -z "$RVC_MODEL" ]; then
      for d in ${cfg.modelDir} ${project}/rvc/logs; do
        if [ -d "$d" ]; then
          RVC_MODEL=$(find "$d" -maxdepth 2 -name '*.pth' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2- || true)
        fi
        [ -n "$RVC_MODEL" ] && break
      done
    fi
    export RVC_MODEL

    RVC_INDEX="''${RVC_INDEX:-}"
    if [ -z "$RVC_INDEX" ] && [ -n "$RVC_MODEL" ] && [ -d ${project}/rvc/logs ]; then
      RVC_INDEX=$(find ${project}/rvc/logs -maxdepth 2 -name 'added_*.index' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2- || true)
    fi
    export RVC_INDEX

    exec "$VENV_PY" ${project}/realtime_serve.py
  '';
in
{
  options.mandragora.voiceRvc = {
    enable = lib.mkEnableOption "headless realtime RVC voice conversion (VoiceMorph.monitor → RvcOut)";
    modelDir = lib.mkOption {
      type = lib.types.str;
      default = "${project}/rvc/assets/weights";
      description = "Directory searched first for the trained .pth model.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.voice-rvc = {
      description = "voice.mvr.ac — realtime RVC voice conversion (GPU)";
      wantedBy = [ "default.target" ];
      after = [ "pipewire.service" ];
      wants = [ "pipewire.service" ];
      environment = {
        RVC_CUDA_GRAPH = "0";
        RVC_F0METHOD = "rmvpe";
        RVC_PITCH = "0";
        RVC_INDEX_RATE = "0";
        RVC_IN_DEVICE = "voice morph sink";
        RVC_OUT_DEVICE = "rvc output";
      };
      path = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.gawk
        pkgs.bash
        pkgs.binutils
      ];
      serviceConfig = {
        ExecStart = "${gpuLock}/bin/gpu-lock run --name voice-rvc --expect 86400 -- ${launcher}";
        Restart = "on-failure";
        RestartSec = "15s";
        TimeoutStartSec = "10min";
        MemoryMax = "16G";
        OOMScoreAdjust = 300;
      };
      unitConfig = {
        ConditionPathExists = [ "/dev/nvidia0" ];
      };
    };
  };
}
