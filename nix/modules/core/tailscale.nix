{ pkgs, ... }:

let
  tailnet = builtins.fromJSON (builtins.readFile ../../snippets/tailnet.json);
in
{
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "client";
  };

  networking.hosts.${tailnet.vps.ip} = [
    "term.mvr.ac"
    "claude.mvr.ac"
    "kindle.mvr.ac"
    "mandragora-vps"
  ];

  networking.hosts.${tailnet.kindle.ip} = [
    "kindle"
  ];

  environment.systemPackages = [ pkgs.tailscale ];
}
