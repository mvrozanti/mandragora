{ config, lib, pkgs, ... }:

{
  sops.secrets."duckdns/token" = {
    sopsFile = ../../secrets/secrets.yaml;
    owner = "root";
    mode = "0400";
  };

  systemd.services.duckdns-update = {
    description = "Push current public IP to DuckDNS";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      LoadCredential = "token:${config.sops.secrets."duckdns/token".path}";
    };
    script = ''
      token=$(cat "$CREDENTIALS_DIRECTORY/token")
      ${pkgs.curl}/bin/curl -fsS -k \
        "https://www.duckdns.org/update?domains=mvrozanti&token=$token&ip=" \
        -o /dev/null
    '';
  };

  systemd.timers.duckdns-update = {
    description = "Run duckdns-update every 5 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "5min";
      AccuracySec = "30s";
      Unit = "duckdns-update.service";
    };
  };
}
