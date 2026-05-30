{ config, pkgs, lib, ... }:

let
  bridge = pkgs.writers.writePython3Bin "watch-judge-bridge" {
    flakeIgnore = [ "E501" "W503" "E402" "E741" ];
  } (builtins.readFile ../../../.local/bin/watch-judge-bridge.py);
in
{
  environment.systemPackages = [ bridge ];

  systemd.user.services.watch-judge = {
    description = "Judge pending watch.mvr.ac events via local gemini CLI";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${bridge}/bin/watch-judge-bridge";
      TimeoutStartSec = "10min";
      Nice = 19;
      Environment = [
        "WATCH_JUDGE_VPS=opc@mandragora-vps"
        "WATCH_JUDGE_MODEL=gemini-2.5-flash"
        "WATCH_JUDGE_LIMIT=10"
        "PATH=/run/current-system/sw/bin:/run/wrappers/bin:/home/m/.nix-profile/bin:/home/m/.local/bin"
      ];
    };
  };

  systemd.user.timers.watch-judge = {
    description = "Watch judge bridge timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitInactiveSec = "5min";
      RandomizedDelaySec = "30s";
      Persistent = true;
    };
  };
}
