{ pkgs, lib, ... }:

let
  effectsDir = ../../snippets/keyledsd-effects;
  effectFiles = builtins.readDir effectsDir;
  keyleds-patched = pkgs.keyleds.overrideAttrs (old: {
    patches = (old.patches or []) ++ [ ./keyleds-xwayland.patch ];
    postInstall = (old.postInstall or "") + ''
      ${lib.concatStringsSep "\n" (map (name:
        "cp ${pkgs.writeText name (builtins.readFile (effectsDir + "/${name}"))} $out/share/keyledsd/effects/${name}"
      ) (builtins.attrNames effectFiles))}
    '';
  });
in
{
  environment.systemPackages = [ keyleds-patched ];

  services.udev.packages = [ keyleds-patched ];

  # keyledsd runs as the user service; give the logged-in seat write access to
  # the Logitech G Pro keyboard's hidraw node. nixpkgs' keyleds package ships
  # no udev rules, so /dev/hidraw* is root-only by default.
  services.udev.extraRules = ''
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="c339", MODE="0660", TAG+="uaccess"
  '';

  systemd.user.services.keyledsd = {
    description = "Keyleds RGB keyboard daemon";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${keyleds-patched}/bin/keyledsd -m ${keyleds-patched}/lib/keyledsd -m ${keyleds-patched}/share/keyledsd/effects";
      Restart = "on-failure";
      RestartSec = "3s";
    };
  };
}
