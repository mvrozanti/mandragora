{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkOption
    types
    mapAttrs'
    nameValuePair
    filterAttrs
    mapAttrsToList
    ;
  cfg = config.mandragora.gpuIdle;
  enabled = filterAttrs (_: c: c.enable) cfg;

  watcher =
    name: c:
    pkgs.writeShellScript "gpu-idle-${name}" ''
      set -euo pipefail
      export PATH=${
        lib.makeBinPath [
          pkgs.iproute2
          pkgs.systemd
          pkgs.coreutils
          pkgs.gnugrep
        ]
      }:$PATH

      UNIT=${lib.escapeShellArg c.unit}
      STATE=''${XDG_RUNTIME_DIR:-/tmp}/gpu-idle-${name}.since
      IDLE=$(( ${toString c.minutes} * 60 ))

      systemctl --user is-active --quiet "$UNIT" || { rm -f "$STATE"; exit 0; }

      # An open page holds a socket, so "no established connections" is the
      # honest idle signal for a web UI: nobody is looking at it.
      conns=$(ss -Htn state established "sport = :${toString c.port}" | grep -c . || true)
      if [ "$conns" -gt 0 ]; then rm -f "$STATE"; exit 0; fi

      now=$(date +%s)
      if [ ! -f "$STATE" ]; then echo "$now" > "$STATE"; exit 0; fi
      since=$(cat "$STATE")
      if [ $(( now - since )) -ge "$IDLE" ]; then
        echo "gpu-idle: $UNIT idle $(( (now - since) / 60 )) min — stopping to free the GPU"
        systemctl --user stop "$UNIT"
        rm -f "$STATE"
      fi
    '';
in
{
  options.mandragora.gpuIdle = mkOption {
    default = { };
    description = ''
      Stop a GPU-holding user service once nothing has connected to it for a
      while. The card is shared between training, image generation, the
      connectome and games, so a service nobody is using should not sit on
      VRAM.

      Idle is measured as zero established TCP connections to the service's
      port. That suits a web UI: an open page holds a socket, so the service
      only stops when nobody is actually looking at it.

      NOTE: this stops the unit outright. There is no socket activation here,
      so the next request fails until something starts it again. Use it for
      services that are cheap to restart or have a wake path of their own.
    '';
    type = types.attrsOf (
      types.submodule (
        { name, ... }:
        {
          options = {
            enable = mkOption {
              type = types.bool;
              default = true;
            };
            unit = mkOption {
              type = types.str;
              description = "The user unit to stop, e.g. \"im-gen-web.service\".";
            };
            port = mkOption {
              type = types.port;
              description = "TCP port whose established connections mean 'in use'.";
            };
            minutes = mkOption {
              type = types.int;
              default = 15;
              description = "Minutes with no connection before the unit is stopped.";
            };
          };
        }
      )
    );
  };

  config = {
    systemd.user.services = mapAttrs' (
      name: c:
      nameValuePair "gpu-idle-${name}" {
        description = "Stop ${c.unit} after ${toString c.minutes} min with no connections";
        unitConfig.ConditionUser = "m";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${watcher name c}";
        };
      }
    ) enabled;

    systemd.user.timers = mapAttrs' (
      name: c:
      nameValuePair "gpu-idle-${name}" {
        description = "Idle check for ${c.unit}";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "3min";
          OnUnitActiveSec = "1min";
          AccuracySec = "20s";
        };
      }
    ) enabled;
  };
}
