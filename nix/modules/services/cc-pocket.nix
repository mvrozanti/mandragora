{ pkgs, ... }:

let
  relayPort = 9090;
  relayDb = "/home/m/.local/share/cc-pocket/relay.db";
  claudeBin = "/etc/profiles/per-user/m/bin/claude-deepseek";
in
{
  mandragora.hub.services.cc-pocket-relay = {
    port = relayPort;
    userService = true;
    systemd = {
      description = "Pairlet relay: zero-knowledge ciphertext broker for remote Claude Code control (tailscale-only)";
      wantedBy = [ "default.target" ];
      after = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        WorkingDirectory = "/home/m";
        ExecStart = "${pkgs.cc-pocket-relay}/bin/cc-pocket-relay --host 0.0.0.0 --port ${toString relayPort} --db ${relayDb}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };

  systemd.user.services.cc-pocket-daemon = {
    description = "Pairlet daemon: drives claude-deepseek for remote control";
    wantedBy = [ "default.target" ];
    after = [ "cc-pocket-relay.service" ];
    wants = [ "cc-pocket-relay.service" ];
    path = [
      "/run/current-system/sw"
      "/etc/profiles/per-user/m"
      "/run/wrappers"
      "/home/m/.nix-profile"
      "/nix/var/nix/profiles/default"
    ];
    environment = {
      CC_POCKET_AUTO_UPDATE = "off";
    };
    serviceConfig = {
      Type = "simple";
      WorkingDirectory = "/home/m";
      ExecStart = "${pkgs.cc-pocket-daemon}/bin/cc-pocket-daemon run --relay ws://127.0.0.1:${toString relayPort} --claude-bin ${claudeBin}";
      Restart = "on-failure";
      RestartSec = "5s";
    };
    unitConfig.ConditionPathExists = claudeBin;
  };
}
