{ pkgs, ... }:

let
  projectDir = "/home/m/Projects/llm-visualizer";
  backendDir = "${projectDir}/backend";
  buildDir = "${projectDir}/frontend/build";
  ldLib = "/run/current-system/sw/share/nix-ld/lib";
in
{
  systemd.user.services.llm-visualizer-backend = {
    description = "llm-visualizer backend — analogy + semantic-arithmetic API (Ollama, tailnet only)";
    wantedBy = [ "default.target" ];
    after = [
      "default.target"
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
    };
    serviceConfig = {
      Type = "simple";
      WorkingDirectory = backendDir;
      ExecStart = "${pkgs.uv}/bin/uv run --project ${projectDir} python main.py";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  systemd.user.services.llm-visualizer-frontend = {
    description = "llm-visualizer frontend — static production build on :3001 (tailnet only)";
    wantedBy = [ "default.target" ];
    after = [ "default.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.python3}/bin/python -m http.server 3001 --bind 0.0.0.0 --directory ${buildDir}";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
