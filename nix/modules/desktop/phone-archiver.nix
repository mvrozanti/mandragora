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
    push
    emu
    gate
    smoke
  ];

  systemd.tmpfiles.rules = [
    "d /home/m/Pictures/PhoneInbox 0755 m users -"
    "d /home/m/Pictures/PhoneInbox/dcim 0755 m users -"
    "d /home/m/Pictures/PhoneInbox/pictures 0755 m users -"
    "d /home/m/Pictures/PhoneInbox/movies 0755 m users -"
    "d /home/m/Pictures/PhoneInbox/whatsapp 0755 m users -"
    "d /home/m/Pictures/PhoneInbox/recordings 0755 m users -"
    "d /home/m/Pictures/PhoneInbox/downloads 0755 m users -"
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
        "PHONE_ARCHIVER_RETENTION_DAYS=0"
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
