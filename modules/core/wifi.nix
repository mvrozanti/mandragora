{ pkgs, ... }:

{
  networking.wireless.iwd = {
    enable = true;
    settings = {
      General.EnableNetworkConfiguration = true;
      Network.NameResolvingService = "systemd";
    };
  };

  environment.systemPackages = [ pkgs.impala ];
}
