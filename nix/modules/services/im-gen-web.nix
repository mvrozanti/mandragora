{ config, lib, pkgs, ... }:

let
  repo = "/home/m/Projects/im-gen";
  webApp = "${repo}/webui/app.py";

  launcher = pkgs.writeShellScript "im-gen-web-launch" ''
    set -euo pipefail
    cd ${repo}

    VENV_PY=${repo}/invokeai-venv/bin/python
    if [ ! -x "$VENV_PY" ]; then
      echo "Run ${repo}/invoke.sh once first to bootstrap invokeai-venv." >&2
      exit 1
    fi

    UV=${repo}/.uv-venv/bin/uv
    ensure_pkg() {
      mod="$1"; pkg="$2"
      if [ -x "$UV" ] && ! "$VENV_PY" -c "import $mod" 2>/dev/null; then
        echo ">> installing $pkg into invokeai-venv ..."
        "$UV" pip install --python "$VENV_PY" "$pkg"
      fi
    }
    ensure_pkg aiohttp aiohttp
    ensure_pkg peft peft
    ensure_pkg PIL Pillow

    LD_EXTRAS=""
    [ -d /run/opengl-driver/lib ] && LD_EXTRAS="$LD_EXTRAS:/run/opengl-driver/lib"
    [ -n "''${NIX_LD_LIBRARY_PATH:-}" ] && LD_EXTRAS="$LD_EXTRAS:$NIX_LD_LIBRARY_PATH"
    [ -d /run/current-system/sw/lib ] && LD_EXTRAS="$LD_EXTRAS:/run/current-system/sw/lib"
    export LD_LIBRARY_PATH="''${LD_EXTRAS#:}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export TRITON_LIBCUDA_PATH="/run/opengl-driver/lib"

    HF_SECRET_PATH="/run/secrets/huggingface/read_token"
    if [ -z "''${HF_TOKEN:-}" ] && [ -r "$HF_SECRET_PATH" ]; then
      HF_TOKEN="$(cat "$HF_SECRET_PATH")"
    fi
    [ -n "''${HF_TOKEN:-}" ] && export HF_TOKEN HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"

    CIVITAI_SECRET_PATH="/run/secrets/civitai/api_key"
    if [ -z "''${CIVITAI_TOKEN:-}" ] && [ -r "$CIVITAI_SECRET_PATH" ]; then
      export CIVITAI_TOKEN="$(cat "$CIVITAI_SECRET_PATH")"
    fi

    export PYTHONPATH="${repo}/webui:/etc/nixos/mandragora/.local/share/gpu-lock''${PYTHONPATH:+:$PYTHONPATH}"
    export CC="${pkgs.gcc}/bin/gcc"
    export CXX="${pkgs.gcc}/bin/g++"

    exec "$VENV_PY" ${webApp} "$@"
  '';
in {
  mandragora.hub.services.im-gen-web = {
    port = 6682;
    userService = true;
    systemd = {
      description = "gen.mvr.ac — Flux web UI with LoRA + history graph";
      wantedBy = [ "default.target" ];
      environment = {
        GEN_HOST = "0.0.0.0";
        GEN_PORT = "6682";
        IM_GEN_DIR = repo;
      };
      path = [ pkgs.coreutils pkgs.bash pkgs.gcc ];
      serviceConfig = {
        Type = "simple";
        WorkingDirectory = repo;
        ExecStart = "${launcher}";
        Restart = "on-failure";
        RestartSec = "10s";
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
      unitConfig = {
        ConditionPathExists = [ "/dev/nvidia0" "${repo}/invokeai-venv/bin/python" "${repo}/bot.py" "${webApp}" ];
      };
    };
  };
}
