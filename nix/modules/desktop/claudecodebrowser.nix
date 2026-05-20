{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.mandragora.claudecodebrowser;

  src = inputs.claudecodebrowser;

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
    allowed_extensions = [ "claudecodebrowser@ligandal.com" ];
  });
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
    environment.systemPackages = [ serverBin stdioBin agentBin ];

    # Firefox native-messaging manifest, system-wide.
    # Path-pinned to the Nix store — restart Firefox after rebuild to pick up changes.
    environment.etc."mozilla/native-messaging-hosts/claudecodebrowser.json".source =
      nativeManifest;

    # Per-user runtime dir with strict perms — holds auto-generated API token.
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
        # Hardening
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
