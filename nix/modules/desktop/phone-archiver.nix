{ config, lib, pkgs, ... }:

let
  pyEnv = pkgs.python3.withPackages (ps: [ ps.pillow ]);
  src = ../../../.local/bin/phone-archiver.py;
  archiver = pkgs.writeShellApplication {
    name = "phone-archiver";
    runtimeInputs = [ pyEnv ];
    text = ''
      exec ${pyEnv}/bin/python ${src} "$@"
    '';
  };
in
{
  environment.systemPackages = [ archiver ];

  systemd.user.services.phone-archiver = {
    description = "Drain ~/Pictures/PhoneInbox into archive (EXIF-dated, sha256-verified)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${archiver}/bin/phone-archiver";
      TimeoutStartSec = "20min";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };

  systemd.user.timers.phone-archiver = {
    description = "Phone inbox archive timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitInactiveSec = "2min";
      RandomizedDelaySec = "30s";
      Persistent = true;
    };
  };
}
