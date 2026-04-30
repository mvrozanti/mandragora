{ config, lib, pkgs, ... }:

let
  dataDir = "/var/lib/seafile";
  network = "seafile-net";
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir}            0755 root root - -"
    "d ${dataDir}/db         0700 999  999  - -"
    "d ${dataDir}/shared     0755 root root - -"
  ];

  sops.secrets."seafile/db-root-password" = {
    sopsFile = ../../secrets/secrets.yaml;
    owner = "root";
    mode = "0400";
  };

  sops.secrets."seafile/admin-password" = {
    sopsFile = ../../secrets/secrets.yaml;
    owner = "root";
    mode = "0400";
  };

  systemd.services.seafile-network = {
    description = "Create Seafile docker network";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    script = ''
      ${pkgs.docker}/bin/docker network inspect ${network} >/dev/null 2>&1 \
        || ${pkgs.docker}/bin/docker network create ${network}
    '';
  };

  virtualisation.oci-containers.containers = {
    seafile-mysql = {
      image = "mariadb:10.11";
      autoStart = true;
      environmentFiles = [
        config.sops.secrets."seafile/db-root-password".path
      ];
      environment = {
        MYSQL_LOG_CONSOLE = "true";
        MARIADB_AUTO_UPGRADE = "1";
      };
      volumes = [ "${dataDir}/db:/var/lib/mysql" ];
      extraOptions = [ "--network=${network}" ];
    };

    seafile-memcached = {
      image = "memcached:1.6.18";
      autoStart = true;
      entrypoint = "memcached";
      cmd = [ "-m" "256" ];
      extraOptions = [ "--network=${network}" ];
    };

    seafile = {
      image = "seafileltd/seafile-mc:latest";
      autoStart = true;
      ports = [ "127.0.0.1:8000:80" ];
      environmentFiles = [
        config.sops.secrets."seafile/db-root-password".path
        config.sops.secrets."seafile/admin-password".path
      ];
      environment = {
        DB_HOST = "seafile-mysql";
        TIME_ZONE = "Etc/UTC";
        SEAFILE_ADMIN_EMAIL = "mvrozanti@hotmail.com";
        SEAFILE_SERVER_LETSENCRYPT = "false";
        SEAFILE_SERVER_HOSTNAME = "mandragora-vps";
      };
      volumes = [ "${dataDir}/shared:/shared" ];
      dependsOn = [ "seafile-mysql" "seafile-memcached" ];
      extraOptions = [ "--network=${network}" ];
    };
  };
}
