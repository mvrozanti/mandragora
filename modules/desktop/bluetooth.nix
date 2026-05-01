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
        Experimental = true;
        FastConnectable = false;
        JustWorksRepairing = "always";
        AutoEnable = true;
      };
      Policy = {
        AutoEnable = true;
      };
    };
  };

  services.blueman.enable = true;

  environment.systemPackages = with pkgs; [
    bluez
    bluez-tools
  ];
}
