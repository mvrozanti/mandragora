{ config, pkgs, ... }:

{
  # NVIDIA & Wayland Base
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    open = true;
    modesetting.enable = true;
    powerManagement.enable = true;
    package = config.boot.kernelPackages.nvidiaPackages.beta;
  };

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}
