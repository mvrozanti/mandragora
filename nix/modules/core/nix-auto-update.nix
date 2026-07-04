{ config, pkgs, ... }:

let
  updateBin = pkgs.writeShellScriptBin "mandragora-update"
    (builtins.readFile ../../../.local/bin/mandragora-update.sh);
in
{
  environment.systemPackages = [ updateBin ];

  systemd.services.mandragora-update-probe = {
    description = "Nightly cache-warm nixpkgs update probe; switches only if a download-only rev is found";
    after = [ "network-online.target" "nix-daemon.service" ];
    wants = [ "network-online.target" ];
    path = [
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
}
