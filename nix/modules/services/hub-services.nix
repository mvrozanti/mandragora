{ config, lib, pkgs, ... }:

let
  inherit (lib) mkOption types filterAttrs mapAttrs' nameValuePair mapAttrsToList unique;
  cfg = config.mandragora.hub.services;
  enabled = filterAttrs (_: s: s.enable) cfg;
  systemSvcs = filterAttrs (_: s: !s.userService) enabled;
  userSvcs = filterAttrs (_: s: s.userService) enabled;
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
        userService = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Emit the unit under `systemd.user.services.${name}` instead of
            `systemd.services.${name}`. The service then runs in the primary
            user's manager (no root, no sudo to restart) and is managed via
            `systemctl --user ...`. The user must have `linger = true` for
            the unit to start at boot rather than at first login.

            User units cannot meaningfully order against system targets such
            as `multi-user.target`; use `default.target` in `wantedBy`. The
            tailscale0 firewall port is still opened at the system level
            regardless of this flag.
          '';
        };
        systemd = mkOption {
          type = types.attrs;
          description = "Body merged into systemd.services.${name} (or systemd.user.services.${name} when userService = true).";
        };
      };
    }));
  };

  config = {
    systemd.services = mapAttrs' (name: svc: nameValuePair name svc.systemd) systemSvcs;
    systemd.user.services = mapAttrs' (name: svc: nameValuePair name svc.systemd) userSvcs;
    networking.firewall.interfaces.tailscale0.allowedTCPPorts =
      unique (mapAttrsToList (_: s: s.port) enabled);
  };
}
