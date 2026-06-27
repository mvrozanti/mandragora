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

  gemma = mkPythonBin "gemma" ../../../.local/bin/gemma.py;
  local-ai-mcp-server = mkPythonBin "local-ai-mcp-server" ../../../.local/bin/local-ai-mcp-server.py;
  gpu-lock = import ../../pkgs/gpu-lock.nix { inherit pkgs; };
  vtagCli = import ../../pkgs/vtag-cli.nix { inherit pkgs; };

  crush-wrapped = pkgs.symlinkJoin {
    name = "crush-wrapped";
    paths = [ pkgs.crush ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/crush \
        --run 'if [ -n "$TMUX" ]; then export TERM=xterm-256color; fi'
    '';
  };

  pullModelService = model: {
    description = "Pre-pull ${model}";
    after = [ "ollama.service" "network-online.target" ];
    requires = [ "ollama.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.curl ];
    script = ''
      for i in $(seq 1 30); do
        curl -fsS http://100.115.80.79:11434/api/version >/dev/null && break
        sleep 1
      done
      exec curl -fsS --no-buffer -X POST http://100.115.80.79:11434/api/pull \
        -H 'Content-Type: application/json' \
        -d '{"model":"${model}","stream":false}'
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "2h";
    };
  };
  sanitizeTag = lib.replaceStrings [ ":" "/" "." "_" ] [ "-" "-" "-" "-" ];
in
{
  options.mandragora = {
    hardware.gpu.vramGB = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Total dedicated GPU VRAM in GB. Gates VRAM-hungry features.";
    };

    ai.agentic = {
      enable = lib.mkEnableOption "Local agentic LLM stack";
      model = lib.mkOption {
        type = lib.types.str;
        default = "gpt-oss:20b";
        description = "Ollama tag for the primary local model.";
      };
    };

    ai.vtag = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Expose vtag / vfind CLIs and pre-pull the VLM model.";
      };
      model = lib.mkOption {
        type = lib.types.str;
        default = "qwen2.5vl:7b";
        description = "Ollama tag for the vtag VLM.";
      };
    };

    ai.uncensored = {
      enable = lib.mkEnableOption "Pre-pull an uncensored / abliterated local model";
      model = lib.mkOption {
        type = lib.types.str;
        default = "huihui_ai/qwen2.5-abliterate:14b";
        description = "Ollama tag for an uncensored / abliterated chat model.";
      };
    };

    ai.extraModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Additional Ollama tags pre-pulled declaratively. These back
        always-on consumers that hardcode their own model (MCP server,
        oterm/gemma, thought embeddings, telegram bot, crush secondary)
        and would otherwise rely on a manual `ollama pull`.
      '';
    };
  };

  config = lib.mkMerge [
    {
      services.ollama = {
        enable = true;
        package = pkgs.ollama-cuda;
        # Bind to all interfaces. The host firewall only opens 11434 on
        # tailscale0 (rule below), so external access stays tailnet-only.
        # Without 0.0.0.0 the localhost consumers (bot.py `_evict_ollama`,
        # llm-via-telegram, crush) all get connection-refused.
        host = "0.0.0.0";
        environmentVariables = {
          OLLAMA_CONTEXT_LENGTH = "16384";
          OLLAMA_MAX_LOADED_MODELS = "1";
          OLLAMA_NUM_PARALLEL = "1";
        };
      };

      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 11434 ];

      systemd.services.ollama = {
        restartIfChanged = false;
        stopIfChanged = false;
        after = [ "tailscaled.service" "network-online.target" ];
        wants = [ "tailscaled.service" "network-online.target" ];
        serviceConfig = {
          Restart = lib.mkForce "on-failure";
          RestartSec = "5s";
          # No more ExecStartPre — the NixOS ollama unit's sandbox denies
          # AF_NETLINK so `ip addr show tailscale0` errors with "Cannot
          # open netlink socket: Address family not supported by
          # protocol" and the unit hangs in activating(start-pre). With
          # host=0.0.0.0 the daemon doesn't need the tailnet IP to be up
          # before binding anyway; the pre-pull units further down
          # retry-with-backoff against the tailnet IP, so a brief
          # interface delay is harmless.
        };
      };


      environment.systemPackages = [
        crush-wrapped
        pkgs.beep
        pkgs.oterm
        gemma
        local-ai-mcp-server
        gpu-lock
      ];

      environment.sessionVariables.BRUNO_PASSTHROUGH = "gemini,qwen";
    }

    (lib.mkIf (cfg.extraModels != [ ]) {
      systemd.services = lib.listToAttrs (map
        (m: lib.nameValuePair "ollama-pull-${sanitizeTag m}" (pullModelService m))
        cfg.extraModels);
    })

    (lib.mkIf cfg.agentic.enable {
      assertions = [{
        assertion = gpu.vramGB != null && gpu.vramGB >= 16;
        message = ''
          mandragora.ai.agentic.enable requires mandragora.hardware.gpu.vramGB >= 16.
          The local model fits in VRAM.
        '';
      }];

      environment.systemPackages = [ ];

      systemd.services.ollama-pull-agentic = {
        description = "Pre-pull primary local model";
        after = [ "ollama.service" "network-online.target" ];
        requires = [ "ollama.service" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.curl ];
        script = ''
          for i in $(seq 1 30); do
            curl -fsS http://100.115.80.79:11434/api/version >/dev/null && break
            sleep 1
          done
          exec curl -fsS --no-buffer -X POST http://100.115.80.79:11434/api/pull \
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

    (lib.mkIf cfg.vtag.enable {
      assertions = [{
        assertion = gpu.vramGB != null && gpu.vramGB >= 12;
        message = ''
          mandragora.ai.vtag.enable requires mandragora.hardware.gpu.vramGB >= 12.
          Qwen2.5-VL 7B Q4_K_M needs ~6 GB plus headroom for Flux coexistence.
        '';
      }];

      environment.systemPackages = [
        vtagCli.vtag
        vtagCli.vfind
        pkgs.exiftool
      ];

      systemd.services.ollama-pull-vtag = {
        description = "Pre-pull vtag VLM";
        after = [ "ollama.service" "network-online.target" ];
        requires = [ "ollama.service" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.curl ];
        script = ''
          for i in $(seq 1 30); do
            curl -fsS http://100.115.80.79:11434/api/version >/dev/null && break
            sleep 1
          done
          exec curl -fsS --no-buffer -X POST http://100.115.80.79:11434/api/pull \
            -H 'Content-Type: application/json' \
            -d '{"model":"${cfg.vtag.model}","stream":false}'
        '';
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "2h";
        };
      };
    })

    (lib.mkIf cfg.uncensored.enable {
      systemd.services.ollama-pull-uncensored = {
        description = "Pre-pull uncensored / abliterated model";
        after = [ "ollama.service" "network-online.target" ];
        requires = [ "ollama.service" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.curl ];
        script = ''
          for i in $(seq 1 30); do
            curl -fsS http://100.115.80.79:11434/api/version >/dev/null && break
            sleep 1
          done
          exec curl -fsS --no-buffer -X POST http://100.115.80.79:11434/api/pull \
            -H 'Content-Type: application/json' \
            -d '{"model":"${cfg.uncensored.model}","stream":false}'
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
