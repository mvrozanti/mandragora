{ config, lib, pkgs, ... }:

{
  systemd.tmpfiles.rules = [
    "d /persistent/etc 0755 root root - -"
    "d /persistent/home 0755 root root - -"
    "d /persistent/home/m 0750 m users - -"
  ] ++ lib.optionals config.services.ollama.enable [
    "d /persistent/var/lib/private 0700 root root - -"
    "d /persistent/var/lib/private/ollama 0700 - - - -"
  ];

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
    ] ++ lib.optionals config.services.ollama.enable [
        { directory = "/var/lib/private"; user = "root"; group = "root"; mode = "0700"; }
        "/var/lib/private/ollama"
      ]
      ++ lib.optional config.services.prometheus.enable
        { directory = "/var/lib/prometheus2"; user = "prometheus"; group = "prometheus"; mode = "0700"; }
      ++ lib.optional config.services.tailscale.enable
        { directory = "/var/lib/tailscale"; user = "root"; group = "root"; mode = "0700"; };
    files = lib.optionals config.services.openssh.enable [
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };
}
