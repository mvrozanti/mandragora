{ config, lib, pkgs, ... }:

# Uses the *same* python venv as im-gen's Telegram bot (invokeai-venv) so we
# don't duplicate torch/diffusers/etc. The wrapper script mirrors bot.sh's
# library-stitching for NixOS-flavored CUDA.

let
  repo = "/home/m/Projects/im-gen";
  webScript = "/persistent/mandragora/.local/share/im-gen-web/gen-web.py";

  launcher = pkgs.writeShellScript "im-gen-web-launch" ''
    set -euo pipefail
    cd ${repo}

    VENV_PY=${repo}/invokeai-venv/bin/python
    if [ ! -x "$VENV_PY" ]; then
      echo "Run ${repo}/invoke.sh once first to bootstrap invokeai-venv." >&2
      exit 1
    fi

    # Ensure aiohttp is available in the venv (one-time op).
    UV=${repo}/.uv-venv/bin/uv
    if [ -x "$UV" ] && ! "$VENV_PY" -c "import aiohttp" 2>/dev/null; then
      echo ">> installing aiohttp into invokeai-venv ..."
      "$UV" pip install --python "$VENV_PY" aiohttp
    fi

    # Same library stitching as bot.sh — needed for torch + CUDA on NixOS.
    LD_EXTRAS=""
    [ -d /run/opengl-driver/lib ] && LD_EXTRAS="$LD_EXTRAS:/run/opengl-driver/lib"
    [ -n "''${NIX_LD_LIBRARY_PATH:-}" ] && LD_EXTRAS="$LD_EXTRAS:$NIX_LD_LIBRARY_PATH"
    [ -d /run/current-system/sw/lib ] && LD_EXTRAS="$LD_EXTRAS:/run/current-system/sw/lib"
    export LD_LIBRARY_PATH="''${LD_EXTRAS#:}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export TRITON_LIBCUDA_PATH="/run/opengl-driver/lib"

    # HF token, gpu-lock path — same as bot.sh.
    HF_SECRET_PATH="/run/secrets/huggingface/read_token"
    if [ -z "''${HF_TOKEN:-}" ] && [ -r "$HF_SECRET_PATH" ]; then
      HF_TOKEN="$(cat "$HF_SECRET_PATH")"
    fi
    [ -n "''${HF_TOKEN:-}" ] && export HF_TOKEN HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"
    export PYTHONPATH="/etc/nixos/mandragora/.local/share/gpu-lock''${PYTHONPATH:+:$PYTHONPATH}"

    exec "$VENV_PY" ${webScript} "$@"
  '';
in {
  mandragora.hub.services.im-gen-web = {
    port = 6682;
    systemd = {
      description = "im-gen web UI — minimal prompt → flux image wrapper";
      after = [ "network.target" "tailscaled.service" ];
      wants = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        GEN_HOST = "0.0.0.0";
        GEN_PORT = "6682";
        IM_GEN_DIR = repo;
        PATH = "/run/current-system/sw/bin:/run/wrappers/bin:/etc/profiles/per-user/m/bin";
      };
      serviceConfig = {
        Type = "simple";
        User = "m";
        Group = "users";
        WorkingDirectory = repo;
        ExecStart = "${launcher}";
        Restart = "on-failure";
        RestartSec = "10s";
        TimeoutStartSec = "5min";
      };
      unitConfig = {
        ConditionPathExists = [ "/dev/nvidia0" "${repo}/invokeai-venv/bin/python" "${repo}/bot.py" ];
      };
    };
  };
}
