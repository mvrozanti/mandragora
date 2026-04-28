{ config, pkgs, lib, ... }:

let
  cfg = config.mandragora.ai;
  gpu = config.mandragora.hardware.gpu;

  mkPythonBin = name: src:
    pkgs.stdenv.mkDerivation {
      inherit name;
      src = src;
      dontUnpack = true;
      installPhase = ''
        mkdir -p $out/bin
        echo "#!${pkgs.python3}/bin/python3" > $out/bin/${name}
        cat $src >> $out/bin/${name}
        chmod +x $out/bin/${name}
      '';
    };

  gemma = mkPythonBin "gemma" ../../.local/bin/gemma.py;
  local-ai-mcp-server = mkPythonBin "local-ai-mcp-server" ../../.local/bin/local-ai-mcp-server.py;
  gpu-lock = import ../../pkgs/gpu-lock.nix { inherit pkgs; };
in
{
  options.mandragora = {
    hardware.gpu.vramGB = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Total dedicated GPU VRAM in GB. Gates VRAM-hungry features.";
    };

    ai.agentic = {
      enable = lib.mkEnableOption "Local agentic LLM stack (qwen2.5:7b + Crush TUI)";
      model = lib.mkOption {
        type = lib.types.str;
        default = "qwen2.5:7b";
        description = "Ollama tag for the primary agentic model.";
      };
    };
  };

  config = lib.mkMerge [
    {
      services.ollama = {
        enable = true;
        package = pkgs.ollama-cuda;
        environmentVariables = {
          OLLAMA_CONTEXT_LENGTH = "40960";
          OLLAMA_MAX_LOADED_MODELS = "1";
          OLLAMA_NUM_PARALLEL = "1";
        };
      };

      systemd.services.ollama = {
        restartIfChanged = false;
        stopIfChanged = false;
      };


      environment.systemPackages = [
        pkgs.crush
        pkgs.beep
        pkgs.oterm
        gemma
        local-ai-mcp-server
        gpu-lock
      ];
    }

    (lib.mkIf cfg.agentic.enable {
      assertions = [{
        assertion = gpu.vramGB != null && gpu.vramGB >= 16;
        message = ''
          mandragora.ai.agentic.enable requires mandragora.hardware.gpu.vramGB >= 16.
          Qwen 2.5 7B (dense) fits fully in 16GB VRAM at Q4.
        '';
      }];

      environment.systemPackages = [ ];

      systemd.services.ollama-pull-agentic = {
        description = "Pre-pull primary agentic model (${cfg.agentic.model})";
        after = [ "ollama.service" "network-online.target" ];
        requires = [ "ollama.service" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.curl ];
        script = ''
          for i in $(seq 1 30); do
            curl -fsS http://127.0.0.1:11434/api/version >/dev/null && break
            sleep 1
          done
          exec curl -fsS --no-buffer -X POST http://127.0.0.1:11434/api/pull \
            -H 'Content-Type: application/json' \
            -d '{"model":"${cfg.agentic.model}","stream":false}'
        '';
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "2h";
        };
      };
    })
  ];
}
