{ pkgs, ... }:
{
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
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

  services.blueman.enable = true;

  environment.systemPackages = with pkgs; [
    bluez
    bluez-tools
  ];
}
