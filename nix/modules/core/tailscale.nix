{ pkgs, ... }:

{
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "client";
  };

  networking.hosts."100.84.78.83" = [ "term.mvr.ac" "claude.mvr.ac" "mandragora-vps" ];

  environment.systemPackages = [ pkgs.tailscale ];
}
