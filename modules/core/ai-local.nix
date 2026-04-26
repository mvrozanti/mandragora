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
in
{
  options.mandragora = {
    hardware.gpu.vramGB = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Total dedicated GPU VRAM in GB. Gates VRAM-hungry features.";
    };

    ai.agentic = {
      enable = lib.mkEnableOption "Local agentic LLM stack (Qwen3-30B-A3B + OpenCode TUI)";
      model = lib.mkOption {
        type = lib.types.str;
        default = "qwen3:30b-a3b";
        description = "Ollama tag for the primary agentic model.";
      };
    };
  };

  config = lib.mkMerge [
    {
      services.ollama = {
        enable = true;
        package = pkgs.ollama-cuda;
      };

      environment.systemPackages = [
        pkgs.oterm
        gemma
        local-ai-mcp-server
      ];
    }

    (lib.mkIf cfg.agentic.enable {
      assertions = [{
        assertion = gpu.vramGB != null && gpu.vramGB >= 16;
        message = ''
          mandragora.ai.agentic.enable requires mandragora.hardware.gpu.vramGB >= 16.
          Qwen3-30B-A3B at Q4_K_M needs ~18GB total with partial CPU offload of idle experts;
          16GB VRAM + 32GB RAM is the documented minimum for this host.
        '';
      }];

      environment.systemPackages = [ pkgs.opencode ];

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
