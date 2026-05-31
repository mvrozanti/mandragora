{ config, pkgs, ... }:

let
  lutris-cache-check = pkgs.writeShellApplication {
    name = "lutris-cache-check";
    runtimeInputs = with pkgs; [ nix curl libnotify systemd coreutils ];
    text = builtins.readFile ../../../.local/bin/lutris-cache-check.sh;
  };
in
{
  home.packages = [ lutris-cache-check ];

  systemd.user.services.lutris-cache-check = {
    Unit = {
      Description = "Probe cache.nixos.org for openldap availability (lutris install gate)";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${lutris-cache-check}/bin/lutris-cache-check";
      Nice = 19;
    };
  };

  systemd.user.timers.lutris-cache-check = {
    Unit.Description = "Periodic cache-availability check for lutris install gate";
    Timer = {
      OnBootSec = "10min";
      OnUnitActiveSec = "6h";
      RandomizedDelaySec = "30min";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
