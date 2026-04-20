{ pkgs, ... }:
{
  services.hardware.openrgb = {
    enable = true;
    motherboard = "amd";
  };

  systemd.services.openrgb-ram-color = {
    description = "Set Kingston Fury DDR5 RGB (ENE DRAM via i2c-6)";
    wantedBy = [ "multi-user.target" ];
    after = [ "openrgb.service" ];
    requires = [ "openrgb.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "openrgb-ram-color" ''
        ${pkgs.openrgb}/bin/openrgb --device 0 --mode direct --color ff0000
        ${pkgs.openrgb}/bin/openrgb --device 1 --mode direct --color ff0000
      '';
    };
  };
}
