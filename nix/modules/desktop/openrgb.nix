{ pkgs, ... }:

let
  detectorAllowExact = [ "ENE SMBus DRAM" ];
  detectorAllowPatterns = [ "^ENE.*DRAM$" "^ENE.*$" ];

  scopeDetectorsPy = pkgs.writeText "openrgb-scope-detectors.py" ''
    import json, re, sys
    allow = set(${builtins.toJSON detectorAllowExact})
    patterns = [re.compile(p) for p in ${builtins.toJSON detectorAllowPatterns}]
    p = sys.argv[1]
    try:
        with open(p) as f:
            cfg = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        sys.exit(0)
    det = cfg.get("Detectors", {}).get("detectors")
    if not isinstance(det, dict):
        sys.exit(0)
    changed = 0
    enabled = 0
    for k in det:
        keep = (k in allow) or any(p.match(k) for p in patterns)
        if det[k] != keep:
            changed += 1
        det[k] = keep
        if keep:
            enabled += 1
    with open(p, "w") as f:
        json.dump(cfg, f, indent=4)
    sys.stderr.write(f"openrgb-scope: {enabled} enabled, {changed} flipped\n")
  '';

  scopeDetectorsScript = pkgs.writeShellScript "openrgb-scope-detectors" ''
    set -eu
    cfg=/var/lib/OpenRGB/OpenRGB.json
    if [ ! -f "$cfg" ]; then
      mkdir -p /var/lib/OpenRGB
      echo '{"Detectors":{"detectors":{}}}' > "$cfg"
    fi
    ${pkgs.python3}/bin/python3 ${scopeDetectorsPy} "$cfg"
  '';

  rescopeAfterEnumScript = pkgs.writeShellScript "openrgb-rescope-after-enum" ''
    set -eu
    cfg=/var/lib/OpenRGB/OpenRGB.json
    [ -f "$cfg" ] || exit 0
    ${pkgs.python3}/bin/python3 ${scopeDetectorsPy} "$cfg"
  '';
in {
  services.hardware.openrgb = {
    enable = true;
    package = pkgs.openrgb-with-all-plugins;
    motherboard = "amd";
  };

  systemd.services.openrgb.serviceConfig.ExecStartPre = [ "${scopeDetectorsScript}" ];
  systemd.services.openrgb.serviceConfig.RestartSec = "5s";
  systemd.services.openrgb.serviceConfig.StartLimitBurst = 10;
  systemd.services.openrgb.serviceConfig.StartLimitIntervalSec = "120s";
  systemd.services.openrgb.after = [ "systemd-modules-load.service" ];

  systemd.services.openrgb-rescope = {
    description = "Re-scope OpenRGB detectors in /var/lib/OpenRGB/OpenRGB.json (file only; effective on next openrgb restart)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${rescopeAfterEnumScript}";
    };
  };

  systemd.timers.openrgb-rescope = {
    description = "Hourly OpenRGB detector re-scope — catches new upstream detectors before they default to enabled";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "1h";
      Unit = "openrgb-rescope.service";
      Persistent = true;
    };
  };

  hardware.i2c.enable = true;
  boot.kernelModules = [ "i2c-dev" ];
}
