{ config, pkgs, ... }:

let
  backup = pkgs.writeShellApplication {
    name = "chess-lens-backup";
    runtimeInputs = [
      pkgs.restic
      pkgs.openssh
      config.virtualisation.docker.package
      pkgs.coreutils
    ];
    text = builtins.readFile ../../snippets/chess-lens-backup.sh;
  };
in
{
  sops.secrets."chess-lens/restic-password" = {
    owner = "m";
    mode = "0400";
  };

  systemd.user.services.chess-lens-backup = {
    description = "Nightly copy of the Chess Lens databases to the VPS: a ClickHouse backup, a Postgres dump and the Redis snapshot, deduplicated by restic";
    serviceConfig = {
      Type = "oneshot";
      Nice = 15;
      IOSchedulingClass = "idle";
      TimeoutStartSec = "2h";
      Environment = [
        "COMPOSE_DIR=%h/Projects/chess-lens-ultimate/backend"
        "REMOTE_USER=opc"
        "VPS_HOST=mandragora-vps"
        "REMOTE_DIR=/home/opc/backups/chess-lens"
        "RESTIC_PASSWORD_FILE=${config.sops.secrets."chess-lens/restic-password".path}"
      ];
      ExecStart = "${backup}/bin/chess-lens-backup";
    };
  };

  systemd.user.timers.chess-lens-backup = {
    description = "Nightly trigger for the Chess Lens database backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 01:30:00";
      Persistent = true;
      RandomizedDelaySec = "20m";
    };
  };
}
