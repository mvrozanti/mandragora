{ pkgs, ... }:

let
  keyleds-patched = pkgs.keyleds.overrideAttrs (old: {
    patches = (old.patches or []) ++ [ ./keyleds-xwayland.patch ];
    postInstall = (old.postInstall or "") + ''
      cp ${pkgs.writeText "lightning.lua" (builtins.readFile ../../snippets/lightning.lua)} \
         $out/share/keyledsd/effects/lightning.lua
    '';
  });
in
{
  environment.systemPackages = [ keyleds-patched ];

  services.udev.packages = [ keyleds-patched ];

  systemd.user.services.keyledsd = {
    description = "Keyleds RGB keyboard daemon";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStartPre = "${pkgs.openrgb}/bin/openrgb --device 0 --mode direct --color 000000";
      ExecStart = "${keyleds-patched}/bin/keyledsd -m ${keyleds-patched}/lib/keyledsd";
      Restart = "on-failure";
      RestartSec = "3s";
    };
  };
}
