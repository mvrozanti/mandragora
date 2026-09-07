{ pkgs, ... }:

let
  projectDir = "/home/m/Projects/llm-visualizer";
  backendDir = "${projectDir}/backend";
  buildDir = "${projectDir}/frontend/build";
  ldLib = "/run/current-system/sw/share/nix-ld/lib";
  supervisor = pkgs.writers.writePython3Bin "llm-visualizer-supervisor" {
    libraries = [ ];
    doCheck = false;
  } (builtins.readFile ../../../.local/bin/llm-visualizer-supervisor.py);
in
{
  systemd.user.sockets.llm-visualizer-backend = {
    description = "llm-visualizer backend socket — on-demand :8000";
    wantedBy = [ "sockets.target" ];
    listenStreams = [ "0.0.0.0:8000" ];
  };

  systemd.user.services.llm-visualizer-backend = {
    description = "llm-visualizer backend — analogy + semantic-arithmetic API (Ollama, on-demand)";
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    wants = [ "network-online.target" ];
    path = [
      pkgs.uv
      pkgs.python3
      pkgs.bash
      pkgs.coreutils
    ];
    environment = {
      LD_LIBRARY_PATH = ldLib;
      PYTHONUTF8 = "1";
      PYTHONIOENCODING = "utf-8";
      OLLAMA_URL = "http://localhost:11434";
      UPSTREAM_ADDR = "127.0.0.1";
      UPSTREAM_PORT = "18000";
      IDLE_TIMEOUT = "900";
      STARTUP_TIMEOUT = "180";
    };
    serviceConfig = {
      Type = "simple";
      WorkingDirectory = backendDir;
      ExecStart = "${supervisor}/bin/llm-visualizer-supervisor ${pkgs.uv}/bin/uv run --project ${projectDir} uvicorn main:app --host 127.0.0.1 --port 18000";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  systemd.user.sockets.llm-visualizer-frontend = {
    description = "llm-visualizer frontend socket — on-demand :3001";
    wantedBy = [ "sockets.target" ];
    listenStreams = [ "0.0.0.0:3001" ];
  };

  systemd.user.services.llm-visualizer-frontend = {
    description = "llm-visualizer frontend — static production build on :3001 (on-demand)";
    environment = {
      UPSTREAM_ADDR = "127.0.0.1";
      UPSTREAM_PORT = "18001";
      IDLE_TIMEOUT = "900";
      STARTUP_TIMEOUT = "60";
    };
    serviceConfig = {
      Type = "simple";
      ExecStart = "${supervisor}/bin/llm-visualizer-supervisor ${pkgs.python3}/bin/python -m http.server 18001 --bind 127.0.0.1 --directory ${buildDir}";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
