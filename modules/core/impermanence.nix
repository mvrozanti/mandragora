{ config, lib, pkgs, ... }:

{
  systemd.tmpfiles.rules = [
    "d /persistent/etc 0755 root root - -"
    "d /persistent/home 0755 root root - -"
    "d /persistent/home/m 0750 m users - -"
  ] ++ lib.optional config.services.ollama.enable
    "d /persistent/var/lib/private/ollama 0700 ollama ollama - -";

  environment.etc."machine-id".source = "/persistent/etc/machine-id";
  environment.etc."nixos/mandragora".source = "/persistent/mandragora";

  environment.persistence."/persistent" = {
    hideMounts = true;
    directories = [
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/var/lib/systemd/timers"
      "/etc/NetworkManager/system-connections"
      { directory = "/home/m"; user = "m"; group = "users"; mode = "0750"; }
    ] ++ lib.optional config.services.ollama.enable "/var/lib/private/ollama";
    files = lib.optionals config.services.openssh.enable [
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };
}
