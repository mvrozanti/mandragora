{ config, lib, pkgs, ... }:

let
  dataDir = "/var/lib/crypto-fetcher";
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0755 root root - -"
  ];

  services.redis.servers.crypto-fetcher = {
    enable = true;
    bind = "127.0.0.1";
    port = 6379;
  };

  virtualisation.oci-containers.containers.crypto-fetcher = {
    image = "crypto-fetcher-binance_fetcher:local";
    autoStart = true;
    environment = {
      REDIS_HOST = "127.0.0.1";
      REDIS_PORT = "6379";
    };
    volumes = [ "${dataDir}:/data" ];
    extraOptions = [ "--network=host" ];
    dependsOn = [ ];
  };
}
