{ lib, pkgs, ... }:

let
  cipherDir = "/home/m/.local/share/im-gen-cipher";
  mountPoint = "/home/m/Pictures/im-gen";
  passFile = "/home/m/.config/im-gen-encfs/passphrase";
in
{
  systemd.user.services.im-gen-cipher = {
    description = "gocryptfs mount for ~/Pictures/im-gen (at-rest encrypted)";
    wantedBy = [ "default.target" ];
    environment = {
      PATH = lib.mkForce "/run/wrappers/bin:/run/current-system/sw/bin";
    };
    serviceConfig = {
      Type = "simple";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${mountPoint} ${cipherDir}";
      ExecStart = "${pkgs.gocryptfs}/bin/gocryptfs -fg -passfile ${passFile} ${cipherDir} ${mountPoint}";
      ExecStartPost = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 40); do ${pkgs.util-linux}/bin/mountpoint -q ${mountPoint} && exit 0; sleep 0.25; done; exit 1'";
      ExecStop = "${pkgs.fuse}/bin/fusermount -u ${mountPoint}";
      Restart = "on-failure";
      RestartSec = "5s";
      NoNewPrivileges = false;
      PrivateMounts = false;
    };
    unitConfig = {
      ConditionPathExists = [
        cipherDir
        passFile
      ];
    };
  };
}
