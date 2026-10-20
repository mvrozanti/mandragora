{ pkgs, ... }:

{
  systemd.services.enp8s0-eee-off = {
    description = "Disable Energy Efficient Ethernet on the RTL8125, a known source of random link drops on that chip";
    wantedBy = [ "multi-user.target" ];
    bindsTo = [ "sys-subsystem-net-devices-enp8s0.device" ];
    after = [ "sys-subsystem-net-devices-enp8s0.device" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.ethtool}/bin/ethtool --eee off enp8s0";
    };
  };
}
