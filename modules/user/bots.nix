{ config, pkgs, lib, ... }:

{
  systemd.user.services.im-gen-bot = {
    Unit = {
      Description = "im-gen Telegram bot (Flux on RTX 5070 Ti)";
      After = [ "graphical-session.target" "network-online.target" ];
      Wants = [ "network-online.target" ];
      ConditionPathExists = [
        "/dev/nvidia0"
        "/home/m/Projects/im-gen/invokeai-venv/bin/python"
        "/home/m/Projects/im-gen/bot.sh"
      ];
    };
    Service = {
      Type = "simple";
      WorkingDirectory = "/home/m/Projects/im-gen";
      ExecStart = "/home/m/Projects/im-gen/bot.sh";
      Restart = "on-failure";
      RestartSec = 10;
      TimeoutStartSec = "5min";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.services.llm-via-telegram = {
    Unit = {
      Description = "LLM-via-Telegram bot (Ollama-backed Qwen, GPU-coordinated)";
      After = [ "graphical-session.target" "network-online.target" ];
      Wants = [ "network-online.target" ];
      ConditionPathExists = [
        "/dev/nvidia0"
        "/home/m/Projects/llm-via-telegram/.env"
        "/home/m/Projects/llm-via-telegram/.venv/bin/python"
      ];
    };
    Service = {
      Type = "simple";
      WorkingDirectory = "/home/m/Projects/llm-via-telegram";
      ExecStart = "/home/m/Projects/llm-via-telegram/.venv/bin/python main.py";
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
