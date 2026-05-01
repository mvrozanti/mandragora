{ pkgs, ... }:
{
  services.pipewire.wireplumber.extraConfig."11-bluez-sink-only" = {
    "monitor.bluez.properties" = {
      "bluez5.roles" = [ "a2dp-sink" ];
    };
  };
}
