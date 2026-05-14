{ pkgs, ... }:
{
  boot.extraModprobeConfig = ''
    # Disable power saving features that cause Realtek/btusb choppiness
    options btusb enable_autosuspend=0
    options rtw89_pci disable_aspm=y
    options rtw89_core disable_lps_deep=y
  '';

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        ControllerMode = "dual";
        Experimental = true;
      };
    };
  };

  # Use a simpler WirePlumber config that doesn't restrict roles or codecs unless needed
  services.pipewire.wireplumber.extraConfig."10-bluez-clean" = {
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
