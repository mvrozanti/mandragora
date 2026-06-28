{ pkgs, ... }:

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
  bootstrap = pkgs.writeShellApplication {
    name = "phone-syncthing-bootstrap";
    runtimeInputs = [ pkgs.android-tools pkgs.curl pkgs.jq ];
    text = builtins.readFile ../../../.local/bin/phone-syncthing-bootstrap.sh;
  };
in
{
  environment.systemPackages = [ archiver bootstrap ];

  systemd.user.services.phone-archiver = {
    description = "Drain ~/Pictures/PhoneInbox into archive (EXIF-dated, sha256-verified)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${archiver}/bin/phone-archiver";
      TimeoutStartSec = "20min";
      Nice = 19;
      IOSchedulingClass = "idle";
      Environment = [
        "PHONE_ARCHIVER_RETENTION_DAYS=30"
      ];
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
