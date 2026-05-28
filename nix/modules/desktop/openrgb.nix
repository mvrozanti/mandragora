{ pkgs, lib, ... }:

let
  detectorAllowlist = [ "ENE SMBus DRAM" ];

  scopeDetectorsPy = pkgs.writeText "openrgb-scope-detectors.py" ''
    import json, sys
    allow = set(${builtins.toJSON detectorAllowlist})
    p = sys.argv[1]
    try:
        with open(p) as f:
            cfg = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        sys.exit(0)
    det = cfg.get("Detectors", {}).get("detectors")
    if not isinstance(det, dict):
        sys.exit(0)
    for k in det:
        det[k] = k in allow
    with open(p, "w") as f:
        json.dump(cfg, f, indent=4)
  '';

  scopeDetectorsScript = pkgs.writeShellScript "openrgb-scope-detectors" ''
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

  # Keep the unit defined (so `sudo systemctl start openrgb` works on demand for
  # driving RAM/motherboard LEDs), but never auto-start it at boot. openrgb's
  # HID probe on the Logitech G Pro keyboard corrupts keyleds' feature-discovery
  # state, leaving the keyboard dark. Boot-time order cannot be reliably fixed,
  # so we keep openrgb off the boot path entirely.
  systemd.services.openrgb.wantedBy = lib.mkForce [];

  # Scope SMBus probing to ENE DRAM only. The upstream config enables ~1600
  # detectors by default; each non-DRAM detector that owns a probe on
  # i2c_piix4 (mobo ARGB chips, GPU controllers, dozens of mouse/keyboard
  # variants the user does not own) contends with ENE writes the
  # wal-to-rgb-daemon is doing at 40 fps and causes visible RAM/AIO flicker.
  systemd.services.openrgb.serviceConfig.ExecStartPre = [ "${scopeDetectorsScript}" ];

  hardware.i2c.enable = true;
  boot.kernelModules = [ "i2c-dev" ];
}
