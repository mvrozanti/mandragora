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
        # Force BREDR mode to stabilize Realtek firmware and discovery
        ControllerMode = "bredr";
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

  # Stabilization tweaks for PipeWire/WirePlumber
  services.pipewire.wireplumber.extraConfig."10-bluez-stability" = {
    "monitor.bluez.properties" = {
      "bluez5.enable-hw-volume" = false;
      "bluez5.roles" = [ "a2dp-sink" ]; # Disable HFP/HSP to prevent choppy switching
    };
  };

  services.blueman.enable = true;

  environment.systemPackages = with pkgs; [
    bluez
    bluez-tools
  ];
}
