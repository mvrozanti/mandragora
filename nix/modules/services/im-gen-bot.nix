{ config, lib, pkgs, ... }:

let
  repo = "/home/m/Projects/im-gen";
in {
  systemd.user.services.im-gen-bot = {
    description = "im-gen Telegram bot (Flux on RTX 5070 Ti)";
    wantedBy = [ "default.target" ];
    path = [ pkgs.coreutils pkgs.bash pkgs.gcc ];
    environment = {
      IM_GEN_DIR = repo;
    };
    serviceConfig = {
      Type = "simple";
      WorkingDirectory = repo;
      ExecStart = "${repo}/bot.sh";
      Restart = "on-failure";
      RestartSec = "10s";
      TimeoutStartSec = "5min";
      Slice = "im-gen.slice";
      MemoryMax = "28G";
      MemorySwapMax = "0";
      OOMScoreAdjust = 1000;
      OOMPolicy = "kill";
      TasksMax = 4096;
      ManagedOOMSwap = "kill";
      ManagedOOMMemoryPressure = "kill";
    };
    unitConfig = {
      ConditionPathExists = [
        "/dev/nvidia0"
        "${repo}/invokeai-venv/bin/python"
        "${repo}/bot.sh"
        "${repo}/bot.py"
      ];
    };
  };
}
