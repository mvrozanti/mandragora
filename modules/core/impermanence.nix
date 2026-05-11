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

  system.activationScripts.purgeBogusCredentialSecret = ''
    if [ -f /persistent/var/lib/systemd/credential.secret ] && \
       [ "$(${pkgs.coreutils}/bin/stat -c %s /persistent/var/lib/systemd/credential.secret)" = "4096" ]; then
      ${pkgs.coreutils}/bin/rm -f /persistent/var/lib/systemd/credential.secret
    fi
  '';

  environment.persistence."/persistent" = {
    hideMounts = true;
    directories = [
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/bluetooth"
      "/var/lib/systemd"
      "/etc/NetworkManager/system-connections"
      { directory = "/home/m"; user = "m"; group = "users"; mode = "0750"; }
    ] ++ lib.optionals (config.services.ollama.enable || config.services.victoriametrics.enable) [
        { directory = "/var/lib/private"; user = "root"; group = "root"; mode = "0700"; }
      ]
      ++ lib.optional config.services.ollama.enable "/var/lib/private/ollama"
      ++ lib.optional config.services.victoriametrics.enable "/var/lib/private/victoriametrics"
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
