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
    runtimeInputs = [
      pkgs.android-tools
      pkgs.curl
      pkgs.jq
    ];
    text = builtins.readFile ../../../.local/bin/phone-syncthing-bootstrap.sh;
  };
  push = pkgs.writeShellApplication {
    name = "phone-push";
    runtimeInputs = [
      pkgs.android-tools
      pkgs.findutils
      pkgs.coreutils
      pkgs.python3
    ];
    text = builtins.readFile ../../../.local/bin/phone-push.sh;
  };
  gate = pkgs.writeShellApplication {
    name = "phone-gate";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
    ];
    text = builtins.readFile ../../../.local/bin/phone-gate.sh;
  };
  smoke = pkgs.writeShellApplication {
    name = "phone-smoke";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    text = builtins.readFile ../../../.local/bin/phone-smoke.sh;
  };
  emu = pkgs.writeShellApplication {
    name = "phone-emu";
    runtimeInputs = [
      pkgs.mpc
      pkgs.findutils
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = builtins.readFile ../../../.local/bin/phone-emu.sh;
  };
in
{
  environment.systemPackages = [
    archiver
    bootstrap
    push
    emu
    gate
    smoke
  ];

  systemd.user.services.phone-archiver = {
    description = "Drain ~/Pictures/PhoneInbox into archive (EXIF-dated, sha256-verified)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${archiver}/bin/phone-archiver";
      TimeoutStartSec = "90min";
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
