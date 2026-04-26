{ config, pkgs, lib, ... }:

{

  systemd.user.services.llm-via-telegram = {
    Unit = {
      Description = "LLM-via-Telegram bot (Ollama-backed Qwen, GPU-coordinated)";
      After = [ "graphical-session.target" "network-online.target" ];
      Wants = [ "network-online.target" ];
      ConditionPathExists = [
        "/dev/nvidia0"
        "/home/m/Projects/llm-via-telegram/.env"
        "/home/m/Projects/llm-via-telegram/pyproject.toml"
      ];
    };
    Service = {
      Type = "simple";
      WorkingDirectory = "/home/m/Projects/llm-via-telegram";
      ExecStart = "${pkgs.uv}/bin/uv run python main.py";
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
