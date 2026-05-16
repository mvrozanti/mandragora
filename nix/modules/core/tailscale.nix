{ config, lib, pkgs, ... }:

{
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "client";
  };

  networking.hosts."100.84.78.83" = [ "term.mvr.ac" "claude.mvr.ac" ];

  environment.systemPackages = [ pkgs.tailscale ];
}
