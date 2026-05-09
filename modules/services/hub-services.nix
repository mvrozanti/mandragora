{ config, lib, pkgs, ... }:

let
  inherit (lib) mkOption mkIf types filterAttrs mapAttrs' nameValuePair mapAttrsToList unique;
  cfg = config.mandragora.hub.services;
  enabled = filterAttrs (_: s: s.enable) cfg;
in {
  options.mandragora.hub.services = mkOption {
    default = {};
    description = ''
      Services published behind the mvrozanti.duckdns.org hub. Each entry
      declares its TCP port and a systemd unit body. The port is opened on
      the tailscale0 interface only — the public firewall (`allowedTCPPorts`)
      is not widened. The VPS-side reverse proxy reaches each service over
      the tailnet via a socat shim on the VPS host.
    '';
    type = types.attrsOf (types.submodule ({ name, ... }: {
      options = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable hub service ${name}.";
        };
        port = mkOption {
          type = types.port;
          description = "TCP port the service listens on; opened on tailscale0 only.";
        };
        systemd = mkOption {
          type = types.attrs;
          description = "Body merged into systemd.services.${name}.";
        };
      };
    }));
  };

  config = {
    systemd.services = mapAttrs' (name: svc: nameValuePair name svc.systemd) enabled;
    networking.firewall.interfaces.tailscale0.allowedTCPPorts =
      unique (mapAttrsToList (_: s: s.port) enabled);
  };
}
