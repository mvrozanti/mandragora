{ config, lib, pkgs, ... }:

let
  pyEnv = pkgs.python3.withPackages (ps: with ps; [ evdev sqlcipher3 ]);

  captureBin = pkgs.writeShellApplication {
    name = "keystats-capture";
    runtimeInputs = [ pkgs.sqlcipher ];
    text = ''
      export KEYSTATS_DB_KEY_FILE="''${KEYSTATS_DB_KEY_FILE:-/run/secrets/keystats-db-key}"
      export KEYSTATS_DB_PATH="''${KEYSTATS_DB_PATH:-/persistent/keystats/stats.db}"
      export KEYSTATS_HYPRLAND_SOCK="''${KEYSTATS_HYPRLAND_SOCK:-}"
      exec ${pyEnv}/bin/python3 ${../../snippets/keystats-capture.py} "$@"
    '';
  };

  webBin = pkgs.writeShellApplication {
    name = "keystats-web";
    runtimeInputs = [ pkgs.sqlcipher ];
    text = ''
      export KEYSTATS_DB_KEY_FILE="''${KEYSTATS_DB_KEY_FILE:-/run/secrets/keystats-db-key}"
      export KEYSTATS_DB_PATH="''${KEYSTATS_DB_PATH:-/persistent/keystats/stats.db}"
      export KEYSTATS_WEB_HOST="''${KEYSTATS_WEB_HOST:-0.0.0.0}"
      export KEYSTATS_WEB_PORT="''${KEYSTATS_WEB_PORT:-6900}"
      exec ${pyEnv}/bin/python3 ${../../snippets/keystats-web.py} "$@"
    '';
  };
in
{
  environment.systemPackages = [ pkgs.sqlcipher captureBin webBin ];

  sops.secrets."keystats/db_key" = {
    owner = "m";
    mode = "0400";
    path = "/run/secrets/keystats-db-key";
  };

  services.udev.packages = [
    (pkgs.writeTextFile {
      name = "keystats-keyd-uaccess";
      destination = "/etc/udev/rules.d/66-keystats-keyd.rules";
      text = ''
        KERNEL=="event*", SUBSYSTEM=="input", ATTRS{name}=="keyd virtual keyboard", TAG+="uaccess"
      '';
    })
  ];

  systemd.tmpfiles.rules = [
    "d /persistent/keystats 0700 m users - -"
  ];

  systemd.user.services.keystats-capture = {
    description = "keystroke aggregator (evdev + Hyprland-gated, SQLCipher)";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" "sops-nix.service" ];
    requires = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${captureBin}/bin/keystats-capture";
      Restart = "on-failure";
      RestartSec = "5s";
      ReadWritePaths = [ "/persistent/keystats" ];
      ProtectHome = "read-only";
      PrivateTmp = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = "AF_UNIX AF_NETLINK";
      MemoryMax = "256M";
      MemorySwapMax = "0";
      OOMScoreAdjust = 500;
    };
  };

  mandragora.hub.services.keystats-web = {
    port = 6900;
    userService = true;
    systemd = {
      description = "kl.mvr.ac — keystats web UI (read-only SQLCipher)";
      wantedBy = [ "default.target" ];
      after = [ "default.target" "keystats-capture.service" ];
      serviceConfig = {
        ExecStart = "${webBin}/bin/keystats-web";
        Restart = "on-failure";
        RestartSec = "5s";
        ReadOnlyPaths = [ "/persistent/keystats" ];
        ProtectHome = "read-only";
        PrivateTmp = true;
        NoNewPrivileges = true;
        RestrictAddressFamilies = "AF_UNIX AF_INET AF_INET6";
        MemoryMax = "128M";
        MemorySwapMax = "0";
        OOMScoreAdjust = 500;
      };
    };
  };
}
