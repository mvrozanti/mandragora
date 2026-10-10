{ pkgs, ... }:

let
  zramWriteback = pkgs.writeShellApplication {
    name = "zram-writeback";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ../../../.local/bin/zram-writeback.sh;
  };
in
{
  systemd.services.zram-writeback = {
    description = "Drain zram pages idle since the previous run (plus incompressible ones) to the SWAP partition, 2 GiB per run at most";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${zramWriteback}/bin/zram-writeback";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };

  systemd.timers.zram-writeback = {
    description = "Every 30 min: move cold swap out of RAM";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30min";
      OnUnitActiveSec = "30min";
    };
  };
}
