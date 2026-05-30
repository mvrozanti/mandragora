{ config, lib, pkgs, ... }:

let
  cfg = config.mandragora.keystats;
  textEnabled = cfg.captureText.enable;
  textAllowlist = builtins.concatStringsSep "," cfg.captureText.allowedClasses;

  pyEnv = pkgs.python3.withPackages (ps: with ps; [ evdev sqlcipher3 bcrypt ]);

  textEnvExports = lib.optionalString textEnabled ''
    export KEYSTATS_TEXT_DB_KEY_FILE="''${KEYSTATS_TEXT_DB_KEY_FILE:-/run/secrets/keystats-text-db-key}"
    export KEYSTATS_TEXT_DB_PATH="''${KEYSTATS_TEXT_DB_PATH:-/persistent/keystats/text.db}"
    export KEYSTATS_TEXT_ALLOWLIST="''${KEYSTATS_TEXT_ALLOWLIST:-${textAllowlist}}"
    export KEYSTATS_TEXT_BLACKLIST_FILE="''${KEYSTATS_TEXT_BLACKLIST_FILE:-/persistent/keystats/blacklist.txt}"
  '';

  webExtraExports = lib.optionalString textEnabled ''
    export KEYSTATS_WORDS_BASICAUTH_FILE="''${KEYSTATS_WORDS_BASICAUTH_FILE:-/run/secrets/keystats-words-basicauth}"
  '';

  captureBin = pkgs.writeShellApplication {
    name = "keystats-capture";
    runtimeInputs = [ pkgs.sqlcipher ];
    text = ''
      export KEYSTATS_DB_KEY_FILE="''${KEYSTATS_DB_KEY_FILE:-/run/secrets/keystats-db-key}"
      export KEYSTATS_DB_PATH="''${KEYSTATS_DB_PATH:-/persistent/keystats/stats.db}"
      export KEYSTATS_HYPRLAND_SOCK="''${KEYSTATS_HYPRLAND_SOCK:-}"
      ${textEnvExports}
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
      ${textEnvExports}
      ${webExtraExports}
      exec ${pyEnv}/bin/python3 ${../../snippets/keystats-web.py} "$@"
    '';
  };

  decayBin = pkgs.writeShellApplication {
    name = "keystats-text-decay";
    runtimeInputs = [ pkgs.sqlcipher pkgs.coreutils ];
    text = ''
      key=$(cat /run/secrets/keystats-text-db-key)
      cutoff=$(( $(date +%s) - 30 * 86400 ))
      ${pkgs.sqlcipher}/bin/sqlcipher /persistent/keystats/text.db <<SQL
      PRAGMA key = "x'$key'";
      PRAGMA cipher_compatibility = 4;
      UPDATE word_count SET count = count / 2 WHERE last_seen < $cutoff;
      DELETE FROM word_count WHERE count = 0;
      SQL
    '';
  };
in
{
  options.mandragora.keystats = {
    captureText = {
      enable = lib.mkEnableOption "typed-word capture for kl.mvr.ac wordcloud (privacy-sensitive)";
      allowedClasses = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = [ "obsidian" "code-url-handler" ];
        description = ''
          Hyprland window classes from which typed words may be captured.
          Empty list = nothing is captured even when enable=true. Do NOT add
          terminals or browsers without understanding that sudo/ssh prompts
          and web login fields are not gated by Hyprland window class.
        '';
      };
    };
  };

  config = {
    environment.systemPackages = [ pkgs.sqlcipher captureBin webBin ]
      ++ lib.optional textEnabled decayBin;

    sops.secrets = {
      "keystats/db_key" = {
        owner = "m";
        mode = "0400";
        path = "/run/secrets/keystats-db-key";
      };
    } // lib.optionalAttrs textEnabled {
      "keystats/text_db_key" = {
        owner = "m";
        mode = "0400";
        path = "/run/secrets/keystats-text-db-key";
      };
      "keystats/words_basicauth" = {
        owner = "m";
        mode = "0400";
        path = "/run/secrets/keystats-words-basicauth";
      };
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
    ] ++ lib.optional textEnabled
      "f /persistent/keystats/blacklist.txt 0600 m users - -";

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

    systemd.user.services.keystats-text-decay = lib.mkIf textEnabled {
      description = "nightly decay of keystats text.db word counts";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${decayBin}/bin/keystats-text-decay";
        ReadWritePaths = [ "/persistent/keystats" ];
        ProtectHome = "read-only";
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    systemd.user.timers.keystats-text-decay = lib.mkIf textEnabled {
      description = "trigger nightly keystats text decay";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
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
  };
}
