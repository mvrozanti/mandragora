{ config, pkgs, ... }:

{
  systemd.tmpfiles.rules = [
    "d /persistent/home 0755 root root - -"
    "d /persistent/home/m 0750 m users - -"
    "d /persistent/var/lib/private/ollama 0700 ollama ollama - -"
  ];

  environment.etc."machine-id".source = "/persistent/etc/machine-id";
  environment.etc."nixos/mandragora".source = "/persistent/mandragora";

  environment.persistence."/persistent" = {
    hideMounts = true;
    directories = [
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/var/lib/private/ollama"
      "/etc/NetworkManager/system-connections"
      { directory = "/home/m"; user = "m"; group = "users"; mode = "0750"; }
    ];
    files = [];
  };
}
