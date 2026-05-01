{ pkgs, ... }:
{
  boot.extraModprobeConfig = ''
    options btusb enable_autosuspend=0
  '';

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        ControllerMode = "bredr";
        Experimental = false;
        FastConnectable = false;
        JustWorksRepairing = "always";
        AutoEnable = true;
      };
      Policy = {
        AutoEnable = true;
      };
    };
  };

  # Disable hardware volume to prevent the 0% lock issue
  services.pipewire.wireplumber.extraConfig."10-bluez-no-hw-volume" = {
    "monitor.bluez.properties" = {
      "bluez5.enable-hw-volume" = false;
    };
  };

  services.blueman.enable = true;

  environment.systemPackages = with pkgs; [
    bluez
    bluez-tools
  ];
}
