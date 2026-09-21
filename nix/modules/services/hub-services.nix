{ config, lib, ... }:

let
  inherit (lib)
    mkOption
    types
    filterAttrs
    mapAttrs'
    nameValuePair
    mapAttrsToList
    unique
    recursiveUpdate
    ;
  cfg = config.mandragora.hub.services;
  enabled = filterAttrs (_: s: s.enable) cfg;
  systemSvcs = filterAttrs (_: s: !s.userService) enabled;
  userSvcs = filterAttrs (_: s: s.userService) enabled;
  defaultsFor =
    svc:
    (if svc.memoryMax == null then { } else { serviceConfig.MemoryMax = svc.memoryMax; })
    // (
      if svc.maxRuntime == null then
        { }
      else
        {
          serviceConfig.RuntimeMaxSec = svc.maxRuntime;
        }
    );
  withDefaults = svc: recursiveUpdate (defaultsFor svc) svc.systemd;
in
{
  options.mandragora.hub.services = mkOption {
    default = { };
    description = ''
      Services published behind the mvrozanti.duckdns.org hub. Each entry
      declares its TCP port and a systemd unit body. The port is opened on
      the tailscale0 interface only — the public firewall (`allowedTCPPorts`)
      is not widened. The VPS-side reverse proxy reaches each service over
      the tailnet via a socat shim on the VPS host.
    '';
    type = types.attrsOf (
      types.submodule (
        { name, ... }:
        {
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
            maxRuntime = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                When set, `serviceConfig.RuntimeMaxSec` — systemd stops the
                unit after this long and `Restart=always` brings it back.

                This is leak tolerance, not a health policy. Several of these
                services grow while completely idle (flybrain-web measured
                11MB fresh against 656MB after ~48 minutes serving zero
                requests), and a periodic reset bounds that without needing
                the leak found first. Restart costs ~1s of downtime, so set
                it only where a brief blip is acceptable.
              '';
            };
            memoryMax = mkOption {
              type = types.nullOr types.str;
              default = "2G";
              description = ''
                Default `serviceConfig.MemoryMax` for ${name}, bounding an
                idle balloon rather than sizing the service. A `MemoryMax`
                set inside `systemd` wins over this; `null` opts out
                entirely, for units whose working set is genuinely large
                (model servers, renderers).

                2G clears the largest observed steady peak among these
                services by better than 2x. A unit that trips it is leaking,
                not busy.
              '';
            };
            systemd = mkOption {
              type = types.attrs;
              description = "Body merged into systemd.services.${name} (or systemd.user.services.${name} when userService = true).";
            };
          };
        }
      )
    );
  };

  config = {
    systemd.services = mapAttrs' (name: svc: nameValuePair name (withDefaults svc)) systemSvcs;
    systemd.user.services = mapAttrs' (
      name: svc:
      nameValuePair name (recursiveUpdate (withDefaults svc) { unitConfig.ConditionUser = "m"; })
    ) userSvcs;
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = unique (
      mapAttrsToList (_: s: s.port) enabled
    );
  };
}
