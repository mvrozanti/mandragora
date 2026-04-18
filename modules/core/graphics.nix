{ config, pkgs, ... }:

{
  # NVIDIA & Wayland Base
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    # Proprietary Driver
    open = false;
    
    # Enable Modesetting (required for Wayland)
    modesetting.enable = true;

    # Nvidia power management (solves suspend/resume corruption as per PRD/software.md)
    powerManagement.enable = true;
    
    # Beta driver (570.x for RTX 5070 Ti)
    package = config.boot.kernelPackages.nvidiaPackages.beta;
  };

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}
