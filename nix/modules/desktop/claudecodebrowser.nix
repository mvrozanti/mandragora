{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.mandragora.claudecodebrowser;

  src = inputs.claudecodebrowser;

  # AMO-namespace-friendly id; differs from upstream's @ligandal.com so we can
  # self-sign under mvrozanti's developer account without collision.
  extensionId = "claudecodebrowser@mvrozanti";

  pyEnv = pkgs.python3.withPackages (ps: [ ps.websockets ]);

  serverBin = pkgs.writeShellScriptBin "claudecodebrowser-server" ''
    exec ${pyEnv}/bin/python ${src}/mcp-server/server.py "$@"
  '';

  stdioBin = pkgs.writeShellScriptBin "claudecodebrowser-mcp" ''
    exec ${pyEnv}/bin/python ${src}/mcp-server/stdio_wrapper.py "$@"
  '';

  agentBin = pkgs.writeShellScriptBin "claudecodebrowser-agent" ''
    exec ${pyEnv}/bin/python ${src}/agent/browser_agent.py "$@"
  '';

  nativeHostBin = pkgs.writeShellScript "claudecodebrowser-native-host" ''
    exec ${pyEnv}/bin/python ${src}/native-host/claudecodebrowser_host.py "$@"
  '';

  nativeManifest = pkgs.writeText "claudecodebrowser.json" (builtins.toJSON {
    name = "claudecodebrowser";
    description = "ClaudeCodeBrowser Native Messaging Host";
    path = "${nativeHostBin}";
    type = "stdio";
    allowed_extensions = [ extensionId ];
  });

  # nixpkgs Firefox is built with --with-default-mozilla-five-home and ships a
  # private $out/lib/mozilla/native-messaging-hosts/ directory. The system-wide
  # /etc/mozilla path is invisible to it; the host package must be added to
  # programs.firefox.nativeMessagingHosts so home-manager symlinks it in.
  nativeHostPkg = pkgs.runCommand "claudecodebrowser-native-messaging-host" { } ''
    install -Dm0644 ${nativeManifest} $out/lib/mozilla/native-messaging-hosts/claudecodebrowser.json
  '';

  # Unsigned xpi with the id rewritten to extensionId. Installable on
  # ESR/Developer/Nightly (signatures.required=false) or via about:debugging.
  # Stable Firefox refuses unsigned in about:addons — use the signed xpi below.
  extensionXpi = pkgs.runCommand "claudecodebrowser-unsigned.xpi" {
    nativeBuildInputs = [ pkgs.zip pkgs.jq ];
  } ''
    cp -r ${src}/extension ext
    chmod -R u+w ext
    jq --arg id "${extensionId}" '
      .browser_specific_settings.gecko.id = $id
    ' ext/manifest.json > ext/manifest.json.tmp
    mv ext/manifest.json.tmp ext/manifest.json
    cd ext
    zip -r -X "$out" . -x '*.DS_Store'
  '';

  xpiPathBin = pkgs.writeShellScriptBin "claudecodebrowser-xpi" ''
    echo ${extensionXpi}
  '';

  # AMO self-sign wrapper. Run as user m. Reads JWT secret from sops at
  # /run/secrets/firefox/developer_hub_key, calls `web-ext sign --channel=unlisted`,
  # writes the signed xpi to /persistent/mandragora/nix/pkgs/claudecodebrowser/signed.xpi.
  # Commit that file to make the module pick it up on next rebuild.
  signedXpiPath = ../../pkgs/claudecodebrowser/signed.xpi;
  hasSignedXpi = builtins.pathExists signedXpiPath;

  signBin = pkgs.writeShellApplication {
    name = "claudecodebrowser-sign";
    runtimeInputs = with pkgs; [ web-ext jq coreutils gnused ];
    text = ''
      set -euo pipefail

      JWT_ISSUER="user:16565816:136"
      JWT_SECRET_FILE="''${CLAUDE_BROWSER_JWT_FILE:-/run/secrets/firefox/developer_hub_key}"
      REPO_ROOT="''${MANDRAGORA_REPO:-/persistent/mandragora}"
      OUT_DIR="$REPO_ROOT/nix/pkgs/claudecodebrowser"
      OUT_XPI="$OUT_DIR/signed.xpi"

      if [ ! -r "$JWT_SECRET_FILE" ]; then
        echo "error: cannot read JWT secret at $JWT_SECRET_FILE" >&2
        exit 1
      fi

      WORK=$(mktemp -d)
      trap 'rm -rf "$WORK"' EXIT
      cp -r ${src}/extension "$WORK/ext"
      chmod -R u+w "$WORK/ext"

      jq --arg id "${extensionId}" '
        .browser_specific_settings.gecko.id = $id
      ' "$WORK/ext/manifest.json" > "$WORK/ext/manifest.json.tmp"
      mv "$WORK/ext/manifest.json.tmp" "$WORK/ext/manifest.json"

      mkdir -p "$OUT_DIR" "$WORK/artifacts"

      JWT_SECRET=$(tr -d '\r\n' < "$JWT_SECRET_FILE")
      web-ext sign \
        --source-dir="$WORK/ext" \
        --artifacts-dir="$WORK/artifacts" \
        --api-key="$JWT_ISSUER" \
        --api-secret="$JWT_SECRET" \
        --channel=unlisted

      SIGNED=$(find "$WORK/artifacts" -name '*.xpi' -print -quit)
      if [ -z "''${SIGNED:-}" ]; then
        echo "error: no signed xpi produced" >&2
        exit 1
      fi
      install -Dm0644 "$SIGNED" "$OUT_XPI"
      echo "wrote $OUT_XPI"
      echo "commit it: git -C $REPO_ROOT add nix/pkgs/claudecodebrowser/signed.xpi && git -C $REPO_ROOT commit -m 'chore(ccb): refresh signed xpi'"
    '';
  };

  installedXpi = if hasSignedXpi then signedXpiPath else extensionXpi;
in {
  options.mandragora.claudecodebrowser = {
    enable = lib.mkEnableOption "ClaudeCodeBrowser MCP + Firefox automation bridge";

    serverService = lib.mkEnableOption ''
      always-on systemd user service for the HTTP backend.
      Disabled by default: the stdio_wrapper spawns server.py on demand
      when Claude Code launches the MCP, which is the safer default.
    '';
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ serverBin stdioBin agentBin xpiPathBin signBin ];

    # Kept for non-Firefox-wrapped consumers (other Mozilla-derived browsers).
    # The nixpkgs Firefox build only sees its own private dir; see nativeHostPkg.
    environment.etc."mozilla/native-messaging-hosts/claudecodebrowser.json".source =
      nativeManifest;

    home-manager.users.m.programs.firefox.nativeMessagingHosts = [ nativeHostPkg ];

    # Stable path for drag-into-about:addons. Source switches to the signed xpi
    # once nix/pkgs/claudecodebrowser/signed.xpi exists in the repo.
    environment.etc."claudecodebrowser/extension.xpi".source = installedXpi;

    systemd.tmpfiles.rules = [
      "d /home/m/.claudecodebrowser            0700 m users - -"
      "d /home/m/.claudecodebrowser/screenshots 0700 m users - -"
      "d /home/m/.claudecodebrowser/logs        0700 m users - -"
    ];

    systemd.user.services.claudecodebrowser = lib.mkIf cfg.serverService {
      description = "ClaudeCodeBrowser HTTP backend (localhost-only)";
      wantedBy = [ "default.target" ];
      environment = {
        CLAUDE_BROWSER_HOST = "127.0.0.1";
        CLAUDE_BROWSER_HTTP_PORT = "8765";
      };
      serviceConfig = {
        Type = "simple";
        ExecStart = "${serverBin}/bin/claudecodebrowser-server";
        Restart = "on-failure";
        RestartSec = "5s";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = false;
        ReadWritePaths = [ "%h/.claudecodebrowser" ];
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_UNIX" ];
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
      };
    };
  };
}
