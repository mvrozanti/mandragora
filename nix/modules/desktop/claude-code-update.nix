{
  config,
  pkgs,
  ...
}:

let
  updateBin = pkgs.writeShellScriptBin "claude-code-update" (
    builtins.readFile ../../../.local/bin/claude-code-update.sh
  );
  notifyBin = pkgs.writeShellScriptBin "telegram-notify" (
    builtins.readFile ../../../.local/bin/telegram-notify.sh
  );
  unitPath = [
    pkgs.curl
    pkgs.jq
    pkgs.git
    pkgs.openssh
    pkgs.gnugrep
    pkgs.gnused
    pkgs.gawk
    pkgs.coreutils
    pkgs.util-linux
    pkgs.procps
    config.nix.package
    "/run/wrappers"
    "/etc/profiles/per-user/m"
    "/run/current-system/sw"
  ];
in
{
  environment.systemPackages = [ updateBin ];

  systemd.services.claude-code-update = {
    description = "Bump the pinned claude-code to npm latest, then rebuild, commit and push";
    after = [
      "network-online.target"
      "nix-daemon.service"
    ];
    wants = [ "network-online.target" ];
    path = unitPath;
    environment = {
      MANDRAGORA_REPO = "/etc/nixos/mandragora";
      MANDRAGORA_NOTIFY_BIN = "${notifyBin}/bin/telegram-notify";
      MANDRAGORA_SWITCH_STABILITY_SECONDS = "0";
    };
    serviceConfig = {
      Type = "oneshot";
      User = "m";
      Group = "users";
      EnvironmentFile = config.sops.secrets."llm_via_telegram/env".path;
      ExecStart = "${updateBin}/bin/claude-code-update";
      Nice = 10;
      IOSchedulingClass = "idle";
      TimeoutStartSec = "2h";
    };
  };

  systemd.timers.claude-code-update = {
    description = "Daily: is there a newer claude-code on npm?";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "05:00:00";
      Persistent = true;
      RandomizedDelaySec = "90m";
    };
  };
}
