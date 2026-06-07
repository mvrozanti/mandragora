{ config, pkgs, lib, ... }:

let
  tripwirePath = lib.makeBinPath [
    pkgs.gawk
    pkgs.coreutils
    pkgs.procps
    pkgs.util-linux
    pkgs.systemd
    pkgs.inetutils
  ];
  tripwireScript = pkgs.writeShellScript "oom-tripwire" (builtins.readFile ../../../.local/bin/oom-tripwire.sh);
in
{
  programs.atop = {
    enable = true;
    atopgpu.enable = true;
    setuidWrapper.enable = true;
    atopService.enable = true;
    atopRotateTimer.enable = true;
    atopacctService.enable = true;
    settings = {
      interval = 60;
    };
  };

  environment.systemPackages = [ pkgs.atop ];

  systemd.tmpfiles.rules = [
    "d /var/log/oom-tripwire 0755 root root 30d"
  ];

  systemd.services.oom-tripwire = {
    description = "Memory pressure tripwire — snapshot top RSS+swap processes when MemAvailable<15% or SwapUsed>70%";
    after = [ "multi-user.target" ];
    wantedBy = [ "multi-user.target" ];
    environment.PATH = tripwirePath;
    serviceConfig = {
      Type = "simple";
      ExecStart = "${tripwireScript}";
      Restart = "always";
      RestartSec = 10;
      Nice = 19;
      IOSchedulingClass = "idle";
      MemoryMax = "64M";
      OOMScoreAdjust = -500;
    };
  };
}
