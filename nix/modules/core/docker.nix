_:

{
  virtualisation.docker = {
    enable = true;
    daemon.settings.data-root = "/persistent/docker";
  };

  users.users.m.extraGroups = [ "docker" ];

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 8080 ];
}
