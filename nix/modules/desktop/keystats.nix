{ config, lib, pkgs, ... }:

let
  cfg = config.mandragora.keystats;
  textEnabled = cfg.captureText.enable;
  textAllowlist = builtins.concatStringsSep "," cfg.captureText.allowedClasses;
  textSecretBlacklist = cfg.captureText.secretBlacklist;
  textBlacklistPath =
    if textSecretBlacklist != null
    then "/run/secrets/keystats-text-blacklist"
    else "/persistent/keystats/blacklist.txt";

  pyEnv = pkgs.python3.withPackages (ps: with ps; [ evdev sqlcipher3 ]);

  textEnvExports = lib.optionalString textEnabled ''
    export KEYSTATS_TEXT_DB_KEY_FILE="''${KEYSTATS_TEXT_DB_KEY_FILE:-/run/secrets/keystats-text-db-key}"
    export KEYSTATS_TEXT_DB_PATH="''${KEYSTATS_TEXT_DB_PATH:-/persistent/keystats/text.db}"
    export KEYSTATS_TEXT_ALLOWLIST="''${KEYSTATS_TEXT_ALLOWLIST:-${textAllowlist}}"
    export KEYSTATS_TEXT_BLACKLIST_FILE="''${KEYSTATS_TEXT_BLACKLIST_FILE:-${textBlacklistPath}}"
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
      exec ${pyEnv}/bin/python3 ${../../snippets/keystats-web.py} "$@"
    '';
  };

  retentionBin = pkgs.writeShellApplication {
    name = "keystats-retention";
    runtimeInputs = [ pkgs.sqlcipher ];
    text = ''
      export KEYSTATS_DB_KEY_FILE="''${KEYSTATS_DB_KEY_FILE:-/run/secrets/keystats-db-key}"
      export KEYSTATS_DB_PATH="''${KEYSTATS_DB_PATH:-/persistent/keystats/stats.db}"
      export KEYSTATS_RAW_RETENTION_DAYS="''${KEYSTATS_RAW_RETENTION_DAYS:-90}"
      export KEYSTATS_WORD_DECAY_DAYS="''${KEYSTATS_WORD_DECAY_DAYS:-30}"
      ${textEnvExports}
      exec ${pyEnv}/bin/python3 ${../../snippets/keystats-retention.py} "$@"
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
          Empty list = capture from EVERY focused window (BLOCKED_CLASSES
          and TITLE_BLOCK_RE in keystats-capture.py still apply, plus the
          sops-protected blacklist in `secretBlacklist`). Sudo/ssh prompts
          in terminals and login fields in browsers are only filtered by
          window-title regex; populate `secretBlacklist` with literal
          master passwords/passphrases as a defense-in-depth net.
        '';
      };
      secretBlacklist = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "keystats/text_blacklist";
        description = ''
          Optional sops secret key (relative to `sops.defaultSopsFile`)
          whose decrypted value is a newline-separated list of words to
          drop before persistence. Mounted at
          /run/secrets/keystats-text-blacklist and used in place of the
          plaintext /persistent/keystats/blacklist.txt. Intended for
          master passwords and other high-sensitivity literals that the
          user does NOT want sitting plaintext on disk. When null, the
          legacy plaintext blacklist.txt is used.
        '';
      };
    };
  };

  config = {
    environment.systemPackages = [ pkgs.sqlcipher captureBin webBin retentionBin ];

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
    } // lib.optionalAttrs (textEnabled && textSecretBlacklist != null) {
      ${textSecretBlacklist} = {
        owner = "m";
        mode = "0400";
        path = "/run/secrets/keystats-text-blacklist";
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
    ] ++ lib.optional (textEnabled && textSecretBlacklist == null)
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

    systemd.user.services.keystats-retention = {
      description = "keystats retention: roll up + prune raw events >90d, decay word counts";
      after = [ "sops-nix.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${retentionBin}/bin/keystats-retention";
        ReadWritePaths = [ "/persistent/keystats" ];
        ProtectHome = "read-only";
        PrivateTmp = true;
        NoNewPrivileges = true;
        RestrictAddressFamilies = "AF_UNIX";
        MemoryMax = "256M";
        MemorySwapMax = "0";
      };
    };

    systemd.user.timers.keystats-retention = {
      description = "trigger daily keystats retention pass";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
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
