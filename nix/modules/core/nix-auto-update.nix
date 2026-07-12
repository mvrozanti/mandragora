{ config, pkgs, ... }:

let
  updateBin = pkgs.writeShellScriptBin "mandragora-update" (
    builtins.readFile ../../../.local/bin/mandragora-update.sh
  );
  watchBin = pkgs.writeShellScriptBin "mandragora-update-watch" (
    builtins.readFile ../../../.local/bin/mandragora-update-watch.sh
  );
  notifyBin = pkgs.writeShellScriptBin "telegram-notify" (
    builtins.readFile ../../../.local/bin/telegram-notify.sh
  );
  buildPath = [
    config.nix.package
    pkgs.nixos-rebuild
    pkgs.git
    pkgs.openssh
    pkgs.curl
    pkgs.gnugrep
    pkgs.gnused
    pkgs.gawk
    pkgs.coreutils
    pkgs.util-linux
    pkgs.procps
    pkgs.systemd
  ];
in
{
  environment.systemPackages = [
    updateBin
    watchBin
    notifyBin
  ];

  systemd.services.mandragora-update-probe = {
    description = "On-demand cache-warm nixpkgs update probe (auto-switch); no timer, manual use only";
    after = [
      "network-online.target"
      "nix-daemon.service"
    ];
    wants = [ "network-online.target" ];
    path = buildPath;
    environment = {
      MANDRAGORA_REPO = "/etc/nixos/mandragora";
      MANDRAGORA_HOST = "mandragora-desktop";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${updateBin}/bin/mandragora-update --auto --settle-days 14";
      Nice = 10;
      IOSchedulingClass = "idle";
      TimeoutStartSec = "3h";
    };
  };

  systemd.services.mandragora-update-watch = {
    description = "Weekly build-test of the pending nixpkgs update; pings when it builds clean (never switches)";
    after = [
      "network-online.target"
      "nix-daemon.service"
    ];
    wants = [ "network-online.target" ];
    path = buildPath ++ [
      watchBin
      notifyBin
    ];
    environment = {
      MANDRAGORA_REPO = "/etc/nixos/mandragora";
      MANDRAGORA_HOST = "mandragora-desktop";
      MANDRAGORA_STATUS_DIR = "/persistent/mandragora-update";
      MANDRAGORA_NOTIFY_BIN = "${notifyBin}/bin/telegram-notify";
    };
    serviceConfig = {
      Type = "oneshot";
      User = "m";
      Group = "users";
      EnvironmentFile = config.sops.secrets."llm_via_telegram/env".path;
      ExecStart = "${watchBin}/bin/mandragora-update-watch";
      Nice = 15;
      IOSchedulingClass = "idle";
      TimeoutStartSec = "4h";
    };
  };

  systemd.timers.mandragora-update-watch = {
    description = "Weekly: is the pending nixpkgs update viable yet?";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 05:00:00";
      Persistent = true;
      RandomizedDelaySec = "2h";
    };
  };
}
